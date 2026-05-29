extends Node

# --- CONFIGURATION ---
# The URL of your FastAPI signaling server (WebSocket)
# Replace with your actual Hugging Face Space WebSocket URL or local address
const SIGNALING_URL = "wss://TON_ESPACE_HUGGING_FACE.hf.space/ws/signaling"

# WebRTC configuration (STUN servers are essential for P2P connection)
const WEBRTC_ICE_SERVERS = [
	{
		"urls": [
			"stun:stun.l.google.com:19302"
		]
	},
	{
		"urls": [
			"turn:free.expressturn.com:3478"
		],
		"username": "000000002095236103",
		"credential": "leoMnuUj+S9hOYscaOxGb5FtRB8="
	},
	{
		"urls": [
			"turn:free.expressturn.com:3478"
		],
		"username": "000000002095236706",
		"credential": "WkD+6ZX/eSrVgYP96hZmTEAwWPs="
	}
]

# --- VARIABLES ---
var _signaling_ws: WebSocketPeer
var _webrtc_peer: WebRTCMultiplayerPeer
var _signaling_room_id: String = ""
var _my_peer_id: String = "" # Our ID for signaling (can be a UUID)
var _is_connected_to_signaling = false
var _webrtc_connections: Dictionary = {} # Stores WebRTCPeerConnection objects

# --- SIGNALS ---
signal signaling_connected()
signal signaling_disconnected()
signal webrtc_connected(peer_id)
signal webrtc_disconnected(peer_id)
signal game_state_received(state_data)
signal join_failed(reason)

func _ready() -> void:
	_signaling_ws = WebSocketPeer.new()
	_webrtc_peer = WebRTCMultiplayerPeer.new()
	
	# Generate a unique ID for signaling if we don't have one
	_my_peer_id = str(randi()) # Simple for now, consider a UUID generator

func _process(_delta: float) -> void:
	_process_signaling()
	
	if _webrtc_peer and get_tree().get_multiplayer().has_multiplayer_peer():
		 _webrtc_peer.poll()

# ==========================================
# 1. SIGNALING CONNECTION (WebSocket)
# ==========================================
func connect_to_matchmaking(room_id: String) -> void:
	_signaling_room_id = room_id
	var full_url = SIGNALING_URL + "/" + room_id + "/" + _my_peer_id
	
	print("Connecting to signaling server at: ", full_url)
	var err = _signaling_ws.connect_to_url(full_url)
	
	if err != OK:
		printerr("Failed to initiate signaling connection.")
		emit_signal("join_failed", "Signaling connection failed")
		return

func _process_signaling() -> void:
	if _signaling_ws.get_ready_state() == WebSocketPeer.STATE_CLOSED:
		if _is_connected_to_signaling:
			_is_connected_to_signaling = false
			print("Signaling server disconnected.")
			emit_signal("signaling_disconnected")
		return
		
	_signaling_ws.poll()
	
	if _signaling_ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		if not _is_connected_to_signaling:
			_is_connected_to_signaling = true
			print("Signaling server connected.")
			emit_signal("signaling_connected")
			
		while _signaling_ws.get_available_packet_count() > 0:
			var packet = _signaling_ws.get_packet()
			var data_str = packet.get_string_from_utf8()
			var msg = JSON.parse_string(data_str)
			if msg:
				_handle_signaling_message(msg)

func _handle_signaling_message(msg: Dictionary) -> void:
	if not msg.has("type") or not msg.has("sender"):
		return
		
	var msg_type = msg["type"]
	var sender_id = msg["sender"]
	
	print("Signaling msg received: ", msg_type, " from ", sender_id)
	
	match msg_type:
		"peer_joined":
			# Another peer joined the signaling room.
			# In a client-server WebRTC setup (where Godot C++ is server),
			# the Godot server should ideally initiate the offer, or the client initiates.
			# Assuming Godot Server acts as the central authority and initiates:
			_create_webrtc_peer_connection(sender_id)
			
		"sdp_offer":
			# Received an offer, we must answer
			_receive_offer(sender_id, msg["sdp"])
			
		"sdp_answer":
			# Received an answer to our offer
			_receive_answer(sender_id, msg["sdp"])
			
		"ice_candidate":
			# Received network routing info
			_receive_ice_candidate(sender_id, msg["media"], msg["index"], msg["name"])
			
		"peer_left":
			_close_webrtc_connection(sender_id)

func _send_signaling_message(msg: Dictionary) -> void:
	if _signaling_ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		var json_str = JSON.stringify(msg)
		_signaling_ws.put_packet(json_str.to_utf8_buffer())

# ==========================================
# 2. WEBRTC CONNECTION SETUP
# ==========================================

func _create_webrtc_peer_connection(remote_peer_id: String) -> WebRTCPeerConnection:
	if _webrtc_connections.has(remote_peer_id):
		return _webrtc_connections[remote_peer_id]
		
	var peer_conn = WebRTCPeerConnection.new()
	var err = peer_conn.initialize({
		"iceServers": WEBRTC_ICE_SERVERS
	})
	
	if err != OK:
		printerr("Failed to initialize WebRTCPeerConnection")
		return null

	# Connect signals for the negotiation process
	peer_conn.session_description_created.connect(_on_session_description_created.bind(remote_peer_id))
	peer_conn.ice_candidate_created.connect(_on_ice_candidate_created.bind(remote_peer_id))
	
	_webrtc_connections[remote_peer_id] = peer_conn
	
	# We add the peer to the WebRTCMultiplayerPeer
	# For a client, we usually connect to ID 1 (the server)
	# The multiplayer peer needs integer IDs.
	# We will hash the string ID to an integer for the WebRTCMultiplayerPeer
	var numeric_id = remote_peer_id.hash() % 2147483647
	
	if not get_tree().get_multiplayer().has_multiplayer_peer():
		 # If we don't have the multiplayer peer setup yet, do it
		 var err_mp = _webrtc_peer.create_client(numeric_id)
		 if err_mp == OK:
			 get_tree().get_multiplayer().multiplayer_peer = _webrtc_peer
	
	_webrtc_peer.add_peer(peer_conn, numeric_id)
	
	return peer_conn

func _on_session_description_created(type: String, sdp: String, remote_peer_id: String) -> void:
	var peer_conn = _webrtc_connections.get(remote_peer_id)
	if not peer_conn: return
	
	peer_conn.set_local_description(type, sdp)
	
	var msg_type = "sdp_offer" if type == "offer" else "sdp_answer"
	
	_send_signaling_message({
		"type": msg_type,
		"target": remote_peer_id,
		"sdp": sdp
	})

func _on_ice_candidate_created(media: String, index: int, name: String, remote_peer_id: String) -> void:
	 _send_signaling_message({
		"type": "ice_candidate",
		"target": remote_peer_id,
		"media": media,
		"index": index,
		"name": name
	})

func _receive_offer(remote_peer_id: String, sdp: String) -> void:
	var peer_conn = _create_webrtc_peer_connection(remote_peer_id)
	if peer_conn:
		peer_conn.set_remote_description("offer", sdp)
		peer_conn.create_answer()

func _receive_answer(remote_peer_id: String, sdp: String) -> void:
	var peer_conn = _webrtc_connections.get(remote_peer_id)
	if peer_conn:
		peer_conn.set_remote_description("answer", sdp)

func _receive_ice_candidate(remote_peer_id: String, media: String, index: int, name: String) -> void:
	var peer_conn = _webrtc_connections.get(remote_peer_id)
	if peer_conn:
		peer_conn.add_ice_candidate(media, index, name)

func _close_webrtc_connection(remote_peer_id: String) -> void:
	if _webrtc_connections.has(remote_peer_id):
		var peer_conn = _webrtc_connections[remote_peer_id]
		peer_conn.close()
		_webrtc_connections.erase(remote_peer_id)
		
		var numeric_id = remote_peer_id.hash() % 2147483647
		if _webrtc_peer and _webrtc_peer.has_peer(numeric_id):
			_webrtc_peer.remove_peer(numeric_id)

# ==========================================
# 3. GAMEPLAY COMMUNICATION
# ==========================================

# This sends a "join" request specifically formatted for your GameServer.cpp
func request_join_game() -> void:
	if not SessionManager.user_data:
		printerr("Cannot join game: No user data in SessionManager")
		return
		
	var join_msg = {
		"type": "join",
		"name": SessionManager.user_data.get("username", "Unknown"),
		"api_key": SessionManager.user_data.get("token", "")
	}
	
	# We send this over the established WebRTC connection to the server (ID 1 usually)
	rpc_id(1, "_receive_game_command", JSON.stringify(join_msg))

# Send player inputs to the server
func send_input(input_data: Dictionary) -> void:
	var msg = {
		"type": "input",
		"payload": input_data
	}
	rpc_id(1, "_receive_game_command", JSON.stringify(msg))

# RPC function to receive game state from the Godot C++ server
@rpc("any_peer", "unreliable")
func _receive_game_command(json_str: String) -> void:
	var msg = JSON.parse_string(json_str)
	if msg:
		if msg.has("type") and msg["type"] == "state":
			 emit_signal("game_state_received", msg)
		elif msg.has("type") and msg["type"] == "joined":
			 print("Successfully joined world ID: ", msg.get("world_id"))
		elif msg.has("type") and msg["type"] == "join_failed":
			 emit_signal("join_failed", msg.get("reason", "Unknown error"))
			 print("Join failed: ", msg.get("reason"))
