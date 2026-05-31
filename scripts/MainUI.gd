## MainUI.gd — Menu principal : Battle Royal (w_by) et Boss Elimination (w_1/2/3)
extends Control

# ── URLs ───────────────────────────────────────────────────────────────────────
# FASTAPI gere : auth, stats, signaling WebRTC (Battle Royal)
const FASTAPI_URL := "https://TON_ESPACE.hf.space"   # <— ton URL FastAPI
# GODOT C++ gere : simulation boss (Boss Elimination), connexion directe WS
const BOSS_SERVER_WS := "ws://127.0.0.1:9099"         # <— serveur Godot C++ en prod

# ── Noeuds principaux ──────────────────────────────────────────────────────────
@onready var main_menu  : Control = $MainMenuScreen
@onready var br_scr     : Control = $BattleRoyaleScreen
@onready var bh_scr     : Control = $BossHuntScreen

# Battle Royal
@onready var br_rooms_list : ItemList = $BattleRoyaleScreen/BRPanel/BRMargin/BRContent/BRRoomsList
@onready var btn_create_br : Button   = $BattleRoyaleScreen/BRPanel/BRMargin/BRContent/ButtonsHBox/BtnCreateBR
@onready var btn_join_br   : Button   = $BattleRoyaleScreen/BRPanel/BRMargin/BRContent/ButtonsHBox/BtnJoinBR
@onready var br_status_lbl : Label    = $BattleRoyaleScreen/BRPanel/BRStatusLabel

# Boss Hunt
@onready var boss_worlds_list : ItemList = $BossHuntScreen/BHPanel/BHMargin/BHContent/BHLeft/BHRoomsList
@onready var bh_status_lbl    : Label    = $BossHuntScreen/BHPanel/BHMargin/BHContent/BHStatusLabel

# ── Clients reseau ─────────────────────────────────────────────────────────────
var _http_br     : HTTPRequest      # requetes FastAPI pour BR
var _boss_ws     : WebSocketPeer    # connexion directe au serveur C++ Godot (Boss)
var _boss_ws_connected : bool = false

func _ready() -> void:
	if not SessionManager.is_logged_in:
		# On utilise call_deferred pour différer le changement de scène
		get_tree().change_scene_to_file.call_deferred("res://scenes/Login.tscn")
		return

	# Requetes HTTP (Battle Royal / FastAPI)
	_http_br = HTTPRequest.new()
	add_child(_http_br)
	_http_br.request_completed.connect(_on_br_http_completed)

	# WebSocket vers le serveur C++ (Boss Elimination uniquement)
	_boss_ws = WebSocketPeer.new()

	_setup_navigation()
	set_process(true)

# ─────────────────────────────────────────────
#  Navigation
# ─────────────────────────────────────────────
func _setup_navigation() -> void:
	# Menu principal
	$MainMenuScreen/VBoxContainer/BtnAvatar.pressed.connect(func():
		get_tree().change_scene_to_file("res://scenes/CharacterScreen.tscn")
	)
	$MainMenuScreen/VBoxContainer/BtnModeBR.pressed.connect(func():
		main_menu.visible = false
		br_scr.visible    = true
		_refresh_br_rooms()
	)
	$MainMenuScreen/VBoxContainer/BtnModeBoss.pressed.connect(func():
		main_menu.visible = false
		bh_scr.visible    = true
		_connect_boss_ws()
	)
	$MainMenuScreen/VBoxContainer/BtnQuit.pressed.connect(func(): get_tree().quit())

	# Retour depuis BR
	$BattleRoyaleScreen/BtnBackFromBR.pressed.connect(func():
		br_scr.visible  = false
		main_menu.visible = true
	)
	# Retour depuis Boss Hunt
	$BossHuntScreen/BtnBackFromBoss.pressed.connect(func():
		bh_scr.visible  = false
		main_menu.visible = true
		_boss_ws.close()
		_boss_ws_connected = false
	)

	# Boutons Battle Royal
	if btn_create_br: btn_create_br.pressed.connect(_on_create_br_pressed)
	if btn_join_br:   btn_join_br.pressed.connect(_on_join_br_pressed)

	# Bouton rejoindre Boss
	$BossHuntScreen/BHContent/BHLeft/BtnJoinBossWorld.pressed.connect(_on_join_boss_pressed)

# ─────────────────────────────────────────────
#  Process (poll WebSocket Boss)
# ─────────────────────────────────────────────
func _process(_delta: float) -> void:
	_poll_boss_ws()

func _poll_boss_ws() -> void:
	if _boss_ws.get_ready_state() == WebSocketPeer.STATE_CLOSED:
		if _boss_ws_connected:
			_boss_ws_connected = false
			_set_bh_status("Serveur boss deconnecte.", Color.ORANGE)
		return

	_boss_ws.poll()

	if _boss_ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		if not _boss_ws_connected:
			_boss_ws_connected = true
			_set_bh_status("Serveur boss connecte.", Color.GREEN)

		while _boss_ws.get_available_packet_count() > 0:
			var pkt      : PackedByteArray = _boss_ws.get_packet()
			var json_str : String          = pkt.get_string_from_utf8()
			_handle_boss_message(json_str)

# ══════════════════════════════════════════════════════════════════════════════
#  BATTLE ROYAL (w_by) — signaling WebRTC via FastAPI
# ══════════════════════════════════════════════════════════════════════════════

func _refresh_br_rooms() -> void:
	_set_br_status("Chargement des salons...", Color.YELLOW)
	_http_br.request(FASTAPI_URL + "/rooms", ["Accept: application/json"], HTTPClient.METHOD_GET)

func _on_br_http_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_set_br_status("Erreur de chargement.", Color.RED); return

	var json = JSON.parse_string(body.get_string_from_utf8())
	if not json or not json.has("rooms"):
		_set_br_status("Aucun salon disponible.", Color.GRAY); return

	br_rooms_list.clear()
	var rooms : Array = json["rooms"]
	if rooms.is_empty():
		_set_br_status("Aucun salon actif — creez-en un !", Color.GRAY)
		return

	_set_br_status("%d salon(s) disponible(s)." % rooms.size(), Color.GREEN)
	for room in rooms:
		var rid   : String = String(room.get("room_id", "???"))
		var count : int    = int(room.get("player_count", 0))
		var full  : bool   = bool(room.get("is_full", false))
		var label := "Salon %s  (%d/16 joueurs)%s" % [rid, count, "  [COMPLET]" if full else ""]
		br_rooms_list.add_item(label)
		br_rooms_list.set_item_metadata(br_rooms_list.get_item_count() - 1, rid)
		if full:
			br_rooms_list.set_item_custom_fg_color(br_rooms_list.get_item_count() - 1, Color.GRAY)

func _on_create_br_pressed() -> void:
	var code := _generate_random_code()
	_set_br_status("Creation du salon %s..." % code, Color.YELLOW)
	_enter_br_room(code)

func _on_join_br_pressed() -> void:
	var sel := br_rooms_list.get_selected_items()
	if sel.is_empty():
		_set_br_status("Selectionnez un salon.", Color.ORANGE); return
	var rid : String = String(br_rooms_list.get_item_metadata(sel[0]))
	_enter_br_room(rid)

func _enter_br_room(room_id: String) -> void:
	var my_peer_id := str(randi() % 100000)
	var ws_url     := FASTAPI_URL.replace("https", "wss").replace("http", "ws")
	var full_url   := ws_url + "/ws/signaling/" + room_id + "/" + my_peer_id

	# Deleguer a NetworkManager qui gere le WebRTC complet
	var nm := get_node_or_null("/root/NetworkManager")
	if nm and nm.has_method("connect_to_matchmaking"):
		nm.call("connect_to_matchmaking", room_id)
		# Transition vers la scene Battle Royal (w_by)
		get_tree().change_scene_to_file("res://scenes/w_by.tscn")
	else:
		_set_br_status("NetworkManager introuvable.", Color.RED)

# ══════════════════════════════════════════════════════════════════════════════
#  BOSS ELIMINATION (w_1 H1 / w_2 H2 / w_3 H3) — serveur Godot C++
# ══════════════════════════════════════════════════════════════════════════════

func _connect_boss_ws() -> void:
	if _boss_ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		return  # deja connecte
	_set_bh_status("Connexion au serveur boss...", Color.YELLOW)
	var err := _boss_ws.connect_to_url(BOSS_SERVER_WS)
	if err != OK:
		_set_bh_status("Impossible de connecter au serveur boss.", Color.RED)

func _handle_boss_message(json_str: String) -> void:
	var parsed = JSON.parse_string(json_str)
	# FIX: typeof() au lieu de get_type() qui n'existe pas sur Dictionary en GDScript
	if typeof(parsed) == TYPE_DICTIONARY:
		var msg := parsed as Dictionary
		var msg_type : String = String(msg.get("type", ""))
		match msg_type:
			"worlds_status":
				_update_boss_worlds_ui(msg.get("worlds", {}))
			"joined":
				_on_boss_joined(msg)
			"join_failed":
				_set_bh_status("Connexion echouee : " + String(msg.get("reason", "")), Color.RED)
			_:
				pass

func _update_boss_worlds_ui(worlds_data: Dictionary) -> void:
	boss_worlds_list.clear()
	# world_id 0→H1 (w_1), 1→H2 (w_2), 2→H3 (w_3)
	var boss_names := ["H1 — Gardien des Cendres", "H2 — Leviathan", "H3 — Spectre Eternal"]
	var scenes     := ["w_1", "w_2", "w_3"]

	for world_key in worlds_data.keys():
		var w_info       : Dictionary = worlds_data[world_key]
		var world_id     : int = int(world_key)
		var status_code  : int = int(w_info.get("status", 0))
		var n_players    : int = int(w_info.get("players", 0))
		var boss_name    : String = boss_names[world_id] if world_id < boss_names.size() else "Boss %d" % (world_id+1)

		var joinable : bool = false
		var status_text : String

		match status_code:
			0: # WORLD_FREE
				status_text = "Libre"
				joinable    = true
			1: # WORLD_BUSY
				if n_players < 4:
					status_text = "En attente (%d/4)" % n_players
					joinable    = true
				else:
					status_text = "Complet"
					joinable    = false
			2: # WORLD_ENDING
				status_text = "Combat en cours"
				joinable    = false
			3: # WORLD_LOCKED
				status_text = "Verrouille"
				joinable    = false
			_:
				status_text = "Occupe"
				joinable    = false

		var line := "%s — %s" % [boss_name, status_text]
		boss_worlds_list.add_item(line)
		var idx := boss_worlds_list.get_item_count() - 1
		boss_worlds_list.set_item_metadata(idx, {
			"world_id":  world_id,
			"scene":     scenes[world_id] if world_id < scenes.size() else "w_1",
			"joinable":  joinable,
		})
		if not joinable:
			boss_worlds_list.set_item_custom_fg_color(idx, Color(0.5, 0.5, 0.5, 1.0))

func _on_join_boss_pressed() -> void:
	var sel := boss_worlds_list.get_selected_items()
	if sel.is_empty():
		_set_bh_status("Selectionnez un monde boss.", Color.ORANGE); return

	var meta : Dictionary = boss_worlds_list.get_item_metadata(sel[0])
	if not meta.get("joinable", false):
		_set_bh_status("Ce monde est inaccessible.", Color.RED); return

	var world_id : int = int(meta.get("world_id", 0))
	_send_join_boss(world_id)

func _send_join_boss(world_id: int) -> void:
	if _boss_ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		_set_bh_status("Non connecte au serveur boss.", Color.RED); return

	var payload := {
		"type":            "join",
		"name":            SessionManager.get_username(),
		"api_key":         SessionManager.get_token(),
		"target_world_id": world_id,
	}
	_boss_ws.put_packet(JSON.stringify(payload).to_utf8_buffer())
	_set_bh_status("Connexion au monde %d..." % (world_id + 1), Color.YELLOW)

func _on_boss_joined(msg: Dictionary) -> void:
	var world_id : int = int(msg.get("world_id", 0))
	# Transition vers la scene du monde boss correspondant (w_1 / w_2 / w_3)
	var scenes : Array[String] = ["res://scenes/w_1.tscn", "res://scenes/w_2.tscn", "res://scenes/w_3.tscn"]
	var scene  : String        = scenes[world_id] if world_id < scenes.size() else scenes[0]
	# Stocker world_id dans SessionManager pour que Boss.gd puisse le lire
	SessionManager.solo_config["world_id"] = world_id
	SessionManager.solo_config["slot"]     = int(msg.get("slot", 0))
	get_tree().change_scene_to_file(scene)

# ─────────────────────────────────────────────
#  Helpers
# ─────────────────────────────────────────────
func _set_br_status(text: String, color: Color) -> void:
	if br_status_lbl:
		br_status_lbl.text = text
		br_status_lbl.add_theme_color_override("font_color", color)

func _set_bh_status(text: String, color: Color) -> void:
	if bh_status_lbl:
		bh_status_lbl.text = text
		bh_status_lbl.add_theme_color_override("font_color", color)

func _generate_random_code() -> String:
	const CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var code := ""
	for i in range(6):
		code += CHARS[randi() % CHARS.length()]
	return code
