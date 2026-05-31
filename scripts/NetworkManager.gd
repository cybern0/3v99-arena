## NetworkManager.gd — Gestionnaire WebRTC pour le Battle Royal (w_by)
## Autoload singleton — Projet > Parametres > Autoload > Nom : NetworkManager
## N'est PAS utilise pour le Boss Elimination (gere par Boss.gd directement).
extends Node

# ─────────────────────────────────────────────
#  Configuration
# ─────────────────────────────────────────────
## URL FastAPI — meme valeur que Login.gd / MainUI.gd
const FASTAPI_BASE := "https://tomefy-py-server.hf.space"

## Serveurs STUN/TURN pour le NAT traversal mobile
const WEBRTC_ICE_SERVERS := [
	{"urls": ["stun:stun.l.google.com:19302"]},
	{"urls": ["stun:stun1.l.google.com:19302"]},
	{
		"urls":       ["free.expressturn.com:3478"],
		"username":   "000000002095236706",
		"credential": "WkD+6ZX/eSrVgYP96hZmTEAwWPs=",
	},
	{
		"urls":       ["turn:free.expressturn.com:3478"],
		"username":   "000000002095236103",
		"credential": "leoMnuUj+S9hOYscaOxGb5FtRB8=",
	},
]

# ─────────────────────────────────────────────
#  Signaux
# ─────────────────────────────────────────────
signal signaling_connected
signal signaling_disconnected
signal webrtc_peer_connected(peer_id: int)
signal webrtc_peer_disconnected(peer_id: int)
signal game_state_received(state: Dictionary)
signal join_failed(reason: String)

# ─────────────────────────────────────────────
#  Etat interne
# ─────────────────────────────────────────────
var _signaling_ws     : WebSocketPeer = WebSocketPeer.new()
var _webrtc_peer      : WebRTCMultiplayerPeer = WebRTCMultiplayerPeer.new()
var _room_id          : String = ""
var _my_peer_id       : String = ""
var _signaling_ready  : bool   = false
var _webrtc_conns     : Dictionary = {}   # remote_peer_id (String) → WebRTCPeerConnection
var _my_network_id : int = 0

func _ready() -> void:
	_my_peer_id = str(randi() % 1000000)

func _process(_delta: float) -> void:
	_process_signaling()
	if _webrtc_peer and get_tree().get_multiplayer().has_multiplayer_peer():
		_webrtc_peer.poll()

# ══════════════════════════════════════════════════════════════════════════════
#  1. CONNEXION AU SIGNALING (WebSocket FastAPI)
# ══════════════════════════════════════════════════════════════════════════════

## Appele par MainUI avant de charger w_by.tscn
func connect_to_matchmaking(room_id: String) -> void:
	_room_id = room_id
	
	# Générer un ID local temporaire
	_my_network_id = randi_range(2, 2147483647) 
	
	# Créer le Mesh IMMÉDIATEMENT
	var err = _webrtc_peer.create_mesh(_my_network_id)
	if err == OK:
		get_tree().get_multiplayer().multiplayer_peer = _webrtc_peer
	
	var base_ws := FASTAPI_BASE.replace("https://", "wss://").replace("http://", "ws://")
	
	# Récupérer le token d'authentification
	var token := SessionManager.get_token()
	
	# Construire l'URL avec le peer_id dans le path ET l'api_key en paramètre de requête
	var url := base_ws + "/ws/signaling/" + room_id + "/" + str(_my_network_id) + "?api_key=" + token
	
	_signaling_ws.connect_to_url(url)

func disconnect_matchmaking() -> void:
	if _signaling_ws.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		_signaling_ws.close()
	_signaling_ready = false
	_webrtc_conns.clear()
	get_tree().get_multiplayer().multiplayer_peer = null

func _process_signaling() -> void:
	var state := _signaling_ws.get_ready_state()

	if state == WebSocketPeer.STATE_CLOSED:
		if _signaling_ready:
			_signaling_ready = false
			signaling_disconnected.emit()
		return

	_signaling_ws.poll()

	if state == WebSocketPeer.STATE_OPEN:
		if not _signaling_ready:
			_signaling_ready = true
			print("[NM] Signaling connecte, room=", _room_id, " peer=", _my_peer_id)
			signaling_connected.emit()

		while _signaling_ws.get_available_packet_count() > 0:
			var pkt  : PackedByteArray = _signaling_ws.get_packet()
			var text : String          = pkt.get_string_from_utf8()
			var msg  : Variant         = JSON.parse_string(text)
			if typeof(msg) == TYPE_DICTIONARY:
				_handle_signaling(msg)

func _handle_signaling(msg: Dictionary) -> void:
	if not msg.has("type") or not msg.has("sender"):
		return
	var msg_type  : String = String(msg["type"])
	var sender_id : String = String(msg["sender"])
	print("[NM] Signal rx: ", msg_type, " from ", sender_id)

	match msg_type:
		"peer_joined":
			# Un nouveau peer rejoint : on initie l'offre
			var conn := _get_or_create_conn(sender_id)
			if conn:
				conn.create_offer()
		"sdp_offer":
			_receive_offer(sender_id, String(msg.get("sdp", "")))
		"sdp_answer":
			_receive_answer(sender_id, String(msg.get("sdp", "")))
		"ice_candidate":
			_receive_ice_candidate(
				sender_id,
				String(msg.get("media", "")),
				int(msg.get("index", 0)),
				String(msg.get("name", ""))
			)
		"peer_left":
			_close_conn(sender_id)

func _send_signal(msg: Dictionary) -> void:
	if _signaling_ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		_signaling_ws.put_packet(JSON.stringify(msg).to_utf8_buffer())

# ══════════════════════════════════════════════════════════════════════════════
#  2. CONNEXIONS WEBRTC
# ══════════════════════════════════════════════════════════════════════════════

func _get_or_create_conn(remote_peer_id: String) -> WebRTCPeerConnection:
	if _webrtc_conns.has(remote_peer_id):
		return _webrtc_conns[remote_peer_id]

	var conn := WebRTCPeerConnection.new()
	conn.initialize({"iceServers": WEBRTC_ICE_SERVERS})
	
	conn.session_description_created.connect(_on_sdp_created.bind(remote_peer_id))
	conn.ice_candidate_created.connect(_on_ice_created.bind(remote_peer_id))

	_webrtc_conns[remote_peer_id] = conn
	
	# On ajoute la connexion de ce joueur au Mesh global
	var numeric_id := absi(remote_peer_id.hash()) % 2147483647 + 1
	_webrtc_peer.add_peer(conn, numeric_id)
	
	return conn

func _on_sdp_created(type: String, sdp: String, remote_peer_id: String) -> void:
	var conn := _webrtc_conns.get(remote_peer_id) as WebRTCPeerConnection
	if not conn: return
	conn.set_local_description(type, sdp)
	_send_signal({
		"type":   "sdp_offer" if type == "offer" else "sdp_answer",
		"target": remote_peer_id,
		"sdp":    sdp,
	})

func _on_ice_created(media: String, index: int, name: String, remote_peer_id: String) -> void:
	_send_signal({
		"type":   "ice_candidate",
		"target": remote_peer_id,
		"media":  media,
		"index":  index,
		"name":   name,
	})

func _receive_offer(remote_peer_id: String, sdp: String) -> void:
	var conn := _get_or_create_conn(remote_peer_id)
	if conn:
		conn.set_remote_description("offer", sdp)
		conn.create_answer()

func _receive_answer(remote_peer_id: String, sdp: String) -> void:
	var conn := _webrtc_conns.get(remote_peer_id) as WebRTCPeerConnection
	if conn:
		conn.set_remote_description("answer", sdp)

func _receive_ice_candidate(remote_peer_id: String, media: String, index: int, name: String) -> void:
	var conn := _webrtc_conns.get(remote_peer_id) as WebRTCPeerConnection
	if conn:
		conn.add_ice_candidate(media, index, name)

func _close_conn(remote_peer_id: String) -> void:
	if _webrtc_conns.has(remote_peer_id):
		var conn := _webrtc_conns[remote_peer_id] as WebRTCPeerConnection
		conn.close()
		_webrtc_conns.erase(remote_peer_id)
		var numeric_id := absi(remote_peer_id.hash()) % 2147483647 + 1
		if _webrtc_peer and _webrtc_peer.has_peer(numeric_id):
			_webrtc_peer.remove_peer(numeric_id)
		webrtc_peer_disconnected.emit(numeric_id)

# ══════════════════════════════════════════════════════════════════════════════
#  3. GAMEPLAY (Battle Royal — P2P via WebRTC)
# ══════════════════════════════════════════════════════════════════════════════

## Envoie l'etat du joueur local a tous les peers (unreliable, basse latence)
func send_player_state(state: Dictionary) -> void:
	if not get_tree().get_multiplayer().has_multiplayer_peer():
		return
	rpc("_receive_player_state", JSON.stringify(state))

## Rejoint le mode Battle Royal avec la session courante
func request_join_br() -> void:
	if not SessionManager.user_data:
		push_error("[NM] Pas de session active")
		return
	# Dans BR on envoie l'etat au serveur via RPC (pas de serveur central C++)
	send_player_state({
		"type":     "join",
		"name":     SessionManager.get_username(),
		"api_key":  SessionManager.get_token(),
	})

@rpc("any_peer", "unreliable")
func _receive_player_state(json_str: String) -> void:
	var msg : Variant = JSON.parse_string(json_str)
	if typeof(msg) == TYPE_DICTIONARY:
		if String(msg.get("type", "")) == "state":
			game_state_received.emit(msg)
