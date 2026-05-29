extends Control

# ── CONFIGURATION DES URLS SATELLITES ──────────────────────────────────────────
const FASTAPI_URL = "http://127.0.0.1:8000" # Remplacez par votre URL de production
const GODOT_SERVER_URL = "ws://127.0.0.1:9099" # Port du serveur C++ game_server.cpp

# ── Noeuds principaux ──────────────────────────────────────────────────────────
@onready var main_menu : Control = $MainMenuScreen
@onready var br_scr    : Control = $BattleRoyaleScreen # Votre écran Battle Royale
@onready var bh_scr    : Control = $BossHuntScreen

# ── NOUVEAUX NOEUDS BATTLE ROYALE (INTERFACE COMPLÉTÉE) ────────────────────────
@onready var br_rooms_list  : ItemList = $BattleRoyaleScreen/BRContent/BRRoomsList
@onready var btn_create_br  : Button   = $BattleRoyaleScreen/BRContent/BtnCreateBR
@onready var btn_join_br    : Button   = $BattleRoyaleScreen/BRContent/BtnJoinBR

# ── NOEUDS BOSS HUNT MIS À JOUR ────────────────────────────────────────────────
@onready var boss_worlds_list : ItemList = $BossHuntScreen/BHContent/BHLeft/BHRoomsList

# Références pour les requêtes API
var http_request : HTTPRequest
var ws_client : WebSocketPeer

func _ready() -> void:
	# Navigation des menus
	$MainMenuScreen/VBoxContainer/BtnModeBR.pressed.connect(func(): 
		main_menu.visible = false
		br_scr.visible = true
		_refresh_battle_royale_rooms()
	)
	
	$MainMenuScreen/VBoxContainer/BtnModeBoss.pressed.connect(func(): 
		main_menu.visible = false
		bh_scr.visible = true
		_connect_to_boss_server_for_status()
	)
	
	$BattleRoyaleScreen/BtnBackFromBR.pressed.connect(func():
		br_scr.visible = false
		main_menu.visible = true
	)
	
	$BossHuntScreen/BtnBackFromBoss.pressed.connect(func():
		bh_scr.visible = false
		main_menu.visible = true
	)
	
	$MainMenuScreen/VBoxContainer/BtnQuit.pressed.connect(func(): get_tree().quit())
	
	# N'oubliez pas de connecter le bouton "Rejoindre le monde" pour les Boss !
	$BossHuntScreen/BHContent/BHLeft/BtnJoinBossWorld.pressed.connect(_on_join_boss_world_clicked)
	# Initialisation du noeud HTTP pour interagir avec FastAPI
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_http_request_completed)
	
	# Connexions des signaux des boutons Battle Royale
	if btn_create_br: btn_create_br.pressed.connect(_on_create_br_pressed)
	if btn_join_br:   btn_join_br.pressed.connect(_on_join_br_pressed)
	
	# Initialisation du client WebSocket pour écouter le serveur de Boss C++
	ws_client = WebSocketPeer.new()
	set_process(true)
	
	# Au démarrage, on rafraîchit les listes
	_refresh_battle_royale_rooms()
	_connect_to_boss_server_for_status()

func _process(_delta: float) -> void:
	if ws_client.get_ready_state() == WebSocketPeer.STATE_OPEN:
		ws_client.poll()
		while ws_client.get_available_packet_count() > 0:
			var packet = ws_client.get_packet()
			var json_str = packet.get_string_from_utf8()
			_handle_boss_server_message(json_str)

# ══════════════════════════════════════════════════════════════════════════════
#  SECTION 1 : BATTLE ROYALE (SIGNALING WEBRTC VIA FASTAPI)
# ══════════════════════════════════════════════════════════════════════════════

func _refresh_battle_royale_rooms() -> void:
	print("[BR] Récupération des salons depuis FastAPI...")
	var url = FASTAPI_URL + "/rooms"
	var headers = ["Accept: application/json"]
	http_request.request(url, headers, HTTPClient.METHOD_GET)

func _on_http_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		print("[BR] Erreur lors de la récupération des salons Battle Royale.")
		return
		
	var json = JSON.parse_string(body.get_string_from_utf8())
	if json and json.has("rooms"):
		br_rooms_list.clear()
		var rooms = json["rooms"]
		for room in rooms:
			var room_id = room["room_id"]
			var count = room["player_count"]
			var display_text = "Salon BR: %s (%d/99 Joueurs)" % [room_id, count]
			br_rooms_list.add_item(display_text)
			# On stocke l'ID réel dans les métadonnées de la ligne
			br_rooms_list.set_item_metadata(br_rooms_list.get_item_count() - 1, room_id)

func _on_create_br_pressed() -> void:
	# Génération d'un code unique aléatoire pour la nouvelle room
	var new_room_code = _generate_random_code()
	print("[BR] Création d'une room Battle Royale avec le code : ", new_room_code)
	
	# Initialisation de la connexion de signaling WebRTC vers l'adresse WebSocket dédiée
	# main.py gère l'auto-création à la connexion sur `/ws/signaling/{room_id}/{peer_id}`
	_enter_br_signaling_room(new_room_code)

func _on_join_br_pressed() -> void:
	var selected_items = br_rooms_list.get_selected_items()
	if selected_items.is_empty():
		print("[BR] Veuillez sélectionner un salon Battle Royale dans la liste.")
		return
		
	var room_id = br_rooms_list.get_item_metadata(selected_items[0])
	print("[BR] Tentative de connexion au salon WebRTC : ", room_id)
	_enter_br_signaling_room(room_id)

func _enter_br_signaling_room(room_id: String) -> void:
	var my_peer_id = str(randi() % 100000) # Identifiant éphémère du joueur
	var signaling_ws_url = FASTAPI_URL.replace("http", "ws") + "/ws/signaling/" + room_id + "/" + my_peer_id
	print("[WebRTC Signaling] Connexion au WebSocket : ", signaling_ws_url)
	# Ici, vous passez la main à votre gestionnaire WebRTC global (ex: NetworkManager)
	# Exemple : NetworkManager.connect_to_signaling(signaling_ws_url)

# ══════════════════════════════════════════════════════════════════════════════
#  SECTION 2 : MONDES DE BOSS (SERVEUR GODOT C++ ACCÈS DYNAMIQUE)
# ══════════════════════════════════════════════════════════════════════════════

func _connect_to_boss_server_for_status() -> void:
	print("[Boss] Connexion au serveur de jeu C++ pour obtenir les statuts...")
	ws_client.connect_to_url(GODOT_SERVER_URL)

func _handle_boss_server_message(json_str: String) -> void:
	var parsed = JSON.parse_string(json_str)
	# Si le serveur renvoie une mise à jour d'état globale ou directe des mondes
	if parsed and parsed.get_type() == Variant.DICTIONARY:
		_update_boss_worlds_ui(parsed)

# Traduction et filtrage selon l'état retourné par GameServer::get_worlds_status()
func _update_boss_worlds_ui(worlds_data: Dictionary) -> void:
	boss_worlds_list.clear()
	
	# Configuration des correspondances d'énumérations de game_server.cpp
	# WORLD_FREE = 0, WORLD_BUSY = 1, ou autres statuts intermédiaires customisés (En attente)
	for world_key in worlds_data.keys():
		var w_info = worlds_data[world_key]
		var world_id = int(world_key)
		var status_code = int(w_info.get("status", 0))
		var current_players = int(w_info.get("players", 0))
		var boss_type = int(w_info.get("boss_type", 1))
		
		var status_text = ""
		var is_joinable = false
		
		# Application stricte de vos règles d'accès :
		match status_code:
			0: # WORLD_FREE
				status_text = "Libre"
				is_joinable = true
			1: # WORLD_BUSY
				# Si le monde est occupé mais qu'il reste de la place, on le considère "En attente"
				if current_players < 4:
					status_text = "En attente (%d/4 Joueurs)" % current_players
					is_joinable = true
				else:
					status_text = "Occupé (Complet)"
					is_joinable = false
			_:
				status_text = "Occupé"
				is_joinable = false
				
		var display_line = "Monde %d [Boss Type %d] ─ %s" % [world_id + 1, boss_type, status_text]
		boss_worlds_list.add_item(display_line)
		
		# Sauvegarde de la configuration d'accès dans les métadonnées de l'index
		var meta_config = {"world_id": world_id, "joinable": is_joinable}
		var last_index = boss_worlds_list.get_item_count() - 1
		boss_worlds_list.set_item_metadata(last_index, meta_config)
		
		# Modification visuelle optionnelle (Griser si inaccessible)
		if not is_joinable:
			boss_worlds_list.set_item_custom_fg_color(last_index, Color(0.5, 0.5, 0.5, 1.0))

# Appelée lors du clic sur le bouton d'action pour valider la règle d'accès
func _on_join_boss_world_clicked() -> void:
	var selected = boss_worlds_list.get_selected_items()
	if selected.is_empty():
		return
		
	var meta = boss_worlds_list.get_item_metadata(selected[0])
	if meta["joinable"] == false:
		print("[Boss Hunt] Action Impossible : Ce monde est actuellement Occupé et inaccessible !")
		# Afficher une alerte UI à l'utilisateur ici si nécessaire
		return
		
	print("[Boss Hunt] Autorisé ! Connexion en cours au Monde ID : ", meta["world_id"])
	# Envoyer la trame JSON {"type": "join", ...} au serveur C++
	_send_join_command_to_server(meta["world_id"])

func _send_join_command_to_server(world_id: int) -> void:
	if ws_client.get_ready_state() == WebSocketPeer.STATE_OPEN:
		var join_payload = {
			"type": "join",
			"name": SessionManager.user_data.get("username", "Player"),
			"api_key": SessionManager.user_data.get("token", ""),
			"target_world_id": world_id
		}
		var bytes = JSON.stringify(join_payload).to_utf8_buffer()
		ws_client.put_packet(bytes)

# Utilitaires de génération
func _generate_random_code() -> String:
	const CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var code := ""
	for i in range(6):
		code += CHARS[randi() % CHARS.length()]
	return code
