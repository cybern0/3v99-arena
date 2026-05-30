## Boss.gd — Controleur reseau du boss (Boss Elimination)
## Attacher sur le CharacterBody3D du boss dans w_1 / w_2 / w_3.
extends CharacterBody3D
class_name BossNetworkController

# ─────────────────────────────────────────────
#  Signaux
# ─────────────────────────────────────────────
signal connection_state_changed(state: int)
signal encounter_state_changed(state: int)
signal world_started(world_id: int)
signal world_ended(world_id: int, reason: String)
signal join_success(world_id: int, slot: int, peer_id: int, player_name: String)
signal join_failed(reason: String)
signal world_state_updated(state: Dictionary)
signal boss_action_updated(action: int, intensity: float)
signal peer_spawned(data: Dictionary)
signal peer_despawned(slot: int)
signal packet_received(message: Dictionary)
signal disconnected

# ─────────────────────────────────────────────
#  Enums (alignes avec server_types.h)
# ─────────────────────────────────────────────
const DEFAULT_SERVER_URL := "ws://127.0.0.1:9099"

enum ConnectionState {
	DISCONNECTED, CONNECTING, CONNECTED, CLOSING, ERROR,
}

enum EncounterState {
	EMPTY, JOINING, WAITING_WORLD, IN_WORLD, ENDING, ENDED_WIN, ENDED_LOSE,
}

enum BossAction {
	IDLE = 0, CENTER = 1, APPROACH = 2, EVASIVE_FLEE = 3,
	JUMP_DODGE = 4, GUARD = 5, LIGHT_ATK = 6, HEAVY_ATK = 7,
}

# ─────────────────────────────────────────────
#  Exports
# ─────────────────────────────────────────────
@export var server_url:           String = DEFAULT_SERVER_URL
@export var auto_connect_on_ready  := false
@export var auto_join_on_connect   := true
@export var debug_packets          := false
@export var movement_speed         := 4.0
@export var rotation_speed         := 6.0

# ─────────────────────────────────────────────
#  Variables membres  (TOUTES declarees ici avant @onready)
# ─────────────────────────────────────────────
## Reference au WorldManager — injectee par WorldManager._bind_scene_entities()
var world_manager: Node = null

var _ws := WebSocketPeer.new()
var _connection_state := ConnectionState.DISCONNECTED
var _encounter_state  := EncounterState.EMPTY

var _current_world_id       := -1
var _current_slot           := -1
var _preferred_world_id     := -1
var _current_boss_action    := BossAction.IDLE
var _current_boss_intensity := 0.0
var _boss_target_position   := Vector3.ZERO
var _boss_target_rotation   := 0.0
var _join_pending           := false

var _session_data    : Dictionary = {}
var _last_world_state: Dictionary = {}
var _last_boss_state : Dictionary = {}
var _last_chars_state: Array      = []

# ─────────────────────────────────────────────
#  Onready (APRES les var, sans doublon)
# ─────────────────────────────────────────────
@onready var animation_player: AnimationPlayer      = get_node_or_null("AnimationPlayer")
## FIX : ray_cast et sync declares une seule fois (doublons supprimes)
@onready var ray_cast:         RayCast3D             = find_child("RayCast3D", true, false)
@onready var sync:             MultiplayerSynchronizer = find_child("MultiplayerSynchronizer", true, false)

# ─────────────────────────────────────────────
#  API WorldManager
# ─────────────────────────────────────────────
func set_world_manager(wm: Node) -> void:
	world_manager = wm
	add_to_group("boss")
	add_to_group("characters")
	if wm and wm.has_method("register_character"):
		wm.register_character(self)

func set_network_authority_from_world(peer_id: int) -> void:
	set_multiplayer_authority(peer_id)
	if sync:
		sync.set_multiplayer_authority(peer_id)

# ─────────────────────────────────────────────
#  _ready
# ─────────────────────────────────────────────
func _ready() -> void:
	set_process(true)
	set_physics_process(true)
	_refresh_session_data()
	if auto_connect_on_ready:
		connect_to_server()

func _process(_delta: float) -> void:
	_poll_socket()

func _physics_process(delta: float) -> void:
	_update_visual_state(delta)

# ─────────────────────────────────────────────
#  WebSocket
# ─────────────────────────────────────────────
func connect_to_server(url: String = "") -> void:
	if url.strip_edges() != "":
		server_url = url.strip_edges()
	if _connection_state in [ConnectionState.CONNECTING, ConnectionState.CONNECTED]:
		return
	var err := _ws.connect_to_url(server_url)
	if err != OK:
		_connection_state = ConnectionState.ERROR
		connection_state_changed.emit(_connection_state)
		push_error("[Boss] Impossible de se connecter a " + server_url)
		return
	_connection_state = ConnectionState.CONNECTING
	connection_state_changed.emit(_connection_state)

func disconnect_from_server() -> void:
	if _ws.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		_connection_state = ConnectionState.CLOSING
		connection_state_changed.emit(_connection_state)
		_ws.close()
	_connection_state = ConnectionState.DISCONNECTED
	_encounter_state  = EncounterState.EMPTY
	connection_state_changed.emit(_connection_state)
	encounter_state_changed.emit(_encounter_state)
	disconnected.emit()

func _poll_socket() -> void:
	var state := _ws.get_ready_state()
	if state == WebSocketPeer.STATE_CLOSED:
		if _connection_state == ConnectionState.CONNECTED:
			_connection_state = ConnectionState.DISCONNECTED
			connection_state_changed.emit(_connection_state)
		return

	_ws.poll()

	if state == WebSocketPeer.STATE_OPEN and _connection_state != ConnectionState.CONNECTED:
		_connection_state = ConnectionState.CONNECTED
		connection_state_changed.emit(_connection_state)
		if auto_join_on_connect and _join_pending:
			_send_join_payload()

	while _ws.get_available_packet_count() > 0:
		var packet := _ws.get_packet()
		var text   := packet.get_string_from_utf8()
		if debug_packets:
			print("[Boss RX] ", text)
		var parsed = JSON.parse_string(text)
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		var msg: Dictionary = parsed
		packet_received.emit(msg)
		_handle_message(msg)

# ─────────────────────────────────────────────
#  Join / Leave
# ─────────────────────────────────────────────
func request_join(target_world_id := -1) -> void:
	_preferred_world_id = target_world_id
	_join_pending       = true
	if _connection_state != ConnectionState.CONNECTED:
		connect_to_server()
		return
	_send_join_payload()

func leave_world() -> void:
	_send_packet({"type": "leave"})
	_encounter_state = EncounterState.EMPTY
	encounter_state_changed.emit(_encounter_state)

func _send_join_payload() -> void:
	_refresh_session_data()

	# Calcul des features ML depuis les stats Supabase
	var stats      : Dictionary = _session_data.get("stats", {})
	var total_stat := max(
		int(stats.get("agility",0)) + int(stats.get("strength",0)) +
		int(stats.get("vitality",0)) + int(stats.get("shield",0)),
		1
	)
	var hist_style := float(stats.get("agility", 0)) / float(total_stat)
	var base_def   := float(stats.get("shield", 0) + stats.get("vitality", 0))
	# Vitalite → HP max (base 100, +1 par point)
	var hp_max     := 100.0 + float(stats.get("vitality", 0))

	var payload := {
		"type":             "join",
		"name":             String(_session_data.get("username", "Player")),
		"api_key":          String(_session_data.get("token", "")),
		"target_world_id":  _preferred_world_id,
		"historical_style": hist_style,
		"base_defense":     base_def,
		"hp":               hp_max,
		"energy":           100.0,
	}
	_join_pending    = false
	_encounter_state = EncounterState.JOINING
	encounter_state_changed.emit(_encounter_state)
	_send_packet(payload)

# ─────────────────────────────────────────────
#  Input gameplay (envoye au serveur C++)
# ─────────────────────────────────────────────
func send_player_input(action: int, combat_hit := false, extra_payload := {}) -> void:
	var payload := {
		"type":       "input",
		"action":     action,
		"combat_hit": combat_hit,
		"payload":    extra_payload,
	}
	_send_packet(payload)

func send_attack(light_attack := true) -> void:
	send_player_input(1, ray_cast != null and ray_cast.is_colliding(), {
		"attack_type": "light" if light_attack else "heavy"
	})

func send_dodge()   -> void: send_player_input(2, false)
func send_special() -> void: send_player_input(3, false)

# ─────────────────────────────────────────────
#  Reception messages serveur
# ─────────────────────────────────────────────
func _handle_message(msg: Dictionary) -> void:
	var msg_type := String(msg.get("type", ""))
	match msg_type:
		"joined":           _on_joined(msg)
		"join_failed":      _on_join_failed(msg)
		"state":            _on_world_state(msg)
		"world_started":    _on_world_started(msg)
		"world_ended":      _on_world_ended(msg)
		"spawn":            peer_spawned.emit(msg)
		"despawn":          peer_despawned.emit(int(msg.get("slot", -1)))
		"boss_state_update": _on_boss_state_update(msg)
		_: pass

func _on_joined(msg: Dictionary) -> void:
	_current_world_id = int(msg.get("world_id", -1))
	_current_slot     = int(msg.get("slot", -1))
	_encounter_state  = EncounterState.IN_WORLD
	encounter_state_changed.emit(_encounter_state)
	join_success.emit(
		_current_world_id, _current_slot,
		int(msg.get("peer_id", -1)),
		String(msg.get("name", "Player"))
	)

func _on_join_failed(msg: Dictionary) -> void:
	_encounter_state = EncounterState.EMPTY
	encounter_state_changed.emit(_encounter_state)
	join_failed.emit(String(msg.get("reason", "unknown")))

func _on_world_started(msg: Dictionary) -> void:
	world_started.emit(int(msg.get("world_id", -1)))

func _on_world_ended(msg: Dictionary) -> void:
	var reason := String(msg.get("reason", "ended"))
	match reason:
		"boss_defeated": _encounter_state = EncounterState.ENDED_WIN
		"all_dead":      _encounter_state = EncounterState.ENDED_LOSE
		_:               _encounter_state = EncounterState.ENDING
	encounter_state_changed.emit(_encounter_state)
	world_ended.emit(int(msg.get("world_id", -1)), reason)

func _on_world_state(msg: Dictionary) -> void:
	_last_world_state = msg.duplicate(true)
	if msg.has("boss"):
		_last_boss_state = msg["boss"].duplicate(true)
		_apply_boss_snapshot(_last_boss_state)
	if msg.has("chars"):
		_last_chars_state = msg["chars"].duplicate(true)
	world_state_updated.emit(_last_world_state)

func _on_boss_state_update(msg: Dictionary) -> void:
	var action    := int(msg.get("state", BossAction.IDLE))
	var intensity := 1.0
	if msg.has("values") and typeof(msg["values"]) == TYPE_ARRAY:
		var values: Array = msg["values"]
		if not values.is_empty():
			intensity = float(values[0])
	_set_boss_action(action, intensity)
	boss_action_updated.emit(action, intensity)

# ─────────────────────────────────────────────
#  State machine boss (visuel client)
# ─────────────────────────────────────────────
func _apply_boss_snapshot(boss_data: Dictionary) -> void:
	var pos = boss_data.get("pos", [0, 0, 0])
	if typeof(pos) == TYPE_ARRAY and pos.size() >= 3:
		_boss_target_position = Vector3(float(pos[0]), float(pos[1]), float(pos[2]))
	var action    := int(boss_data.get("action", BossAction.IDLE))
	var hp        := float(boss_data.get("hp",     1.0))
	var energy    := float(boss_data.get("energy", 1.0))
	var intensity := clampf((hp + energy) * 0.5, 0.0, 1.0)
	_set_boss_action(action, intensity)

func _set_boss_action(action: int, intensity: float) -> void:
	if action == _current_boss_action and is_equal_approx(intensity, _current_boss_intensity):
		return
	_exit_state(_current_boss_action)
	_current_boss_action    = action
	_current_boss_intensity = intensity
	_enter_state(_current_boss_action)

func _enter_state(state: int) -> void:
	match state:
		BossAction.IDLE:         _play_anim_safe("idle")
		BossAction.CENTER:       _play_anim_safe("move")
		BossAction.APPROACH:     _play_anim_safe("run")
		BossAction.EVASIVE_FLEE: _play_anim_safe("evade")
		BossAction.JUMP_DODGE:   _play_anim_safe("jump")
		BossAction.GUARD:        _play_anim_safe("guard")
		BossAction.LIGHT_ATK:    _play_anim_safe("attack_light")
		BossAction.HEAVY_ATK:    _play_anim_safe("attack_heavy")

func _exit_state(_state: int) -> void:
	pass

func _update_visual_state(delta: float) -> void:
	global_position = global_position.lerp(
		_boss_target_position,
		clampf(delta * movement_speed, 0.0, 1.0)
	)
	match _current_boss_action:
		BossAction.APPROACH:     velocity = transform.basis.z * -movement_speed
		BossAction.EVASIVE_FLEE: velocity = transform.basis.z *  movement_speed
		BossAction.JUMP_DODGE:   velocity.y = 6.0 * _current_boss_intensity
		_:                       velocity = velocity.lerp(Vector3.ZERO, delta * 4.0)
	move_and_slide()

# ─────────────────────────────────────────────
#  Utilitaires
# ─────────────────────────────────────────────
func _refresh_session_data() -> void:
	var sm := get_node_or_null("/root/SessionManager")
	if sm:
		var data = sm.get("user_data")
		if typeof(data) == TYPE_DICTIONARY:
			_session_data = data.duplicate(true)
		# Injecter aussi les stats pour le calcul des features
		var stats = sm.get("stats")
		if typeof(stats) == TYPE_DICTIONARY:
			_session_data["stats"] = stats

func _play_anim_safe(anim_name: String) -> void:
	if animation_player and animation_player.has_animation(anim_name):
		animation_player.play(anim_name)

func _send_packet(payload: Dictionary) -> void:
	if _ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	var json_text := JSON.stringify(payload)
	if debug_packets:
		print("[Boss TX] ", json_text)
	_ws.put_packet(json_text.to_utf8_buffer())

func get_last_world_state()      -> Dictionary: return _last_world_state.duplicate(true)
func get_last_boss_state()       -> Dictionary: return _last_boss_state.duplicate(true)
func get_last_characters_state() -> Array:      return _last_chars_state.duplicate(true)
