extends Node3D

var characters : Array[CharacterBody3D] = []
var player_character : CharacterBody3D  = null
var camera_tps : Camera3D = null
var camera_fps : Camera3D = null
var use_fps    : bool     = false

@onready var spawn_point: Node3D = $Spawnable

func _ready() -> void:
	_spawn_selected_avatar()

	# Attendre un frame pour que _ready() du Player soit exécuté
	# et qu'il s'ajoute bien au groupe "Characters"
	await get_tree().process_frame

	var chars := get_tree().get_nodes_in_group("Characters")
	characters.clear()
	for c in chars:
		if c is CharacterBody3D:
			characters.append(c as CharacterBody3D)

	if characters.size() > 0:
		player_character = characters[0]

	camera_tps = $CameraTPS if has_node("CameraTPS") else null
	camera_fps = $CameraFPS if has_node("CameraFPS") else null

	# ── FIX : _setup_camera appelé une seule fois, après lecture SessionManager ──
	if has_node("/root/SessionManager"):
		var sm = get_node("/root/SessionManager")
		if sm.solo_config.has("camera"):
			use_fps = (sm.solo_config["camera"] == "FPS")
	_setup_camera()

func _spawn_selected_avatar() -> void:
	var sm := get_node_or_null("/root/SessionManager")
	if not sm:
		push_warning("[WorldManager] SessionManager non trouvé, modèle par défaut")
		return

	var model_name: String = sm.selected_model if sm.selected_model else "Model 1"

	var MODEL_SCENES := {
		"Model 1": preload("res://scenes/P1.tscn"),
		"Model 2": preload("res://scenes/P2.tscn"),
	}

	if not MODEL_SCENES.has(model_name):
		model_name = "Model 1"

	var scene: PackedScene = MODEL_SCENES[model_name]
	if not scene:
		push_error("[WorldManager] Scène introuvable : " + model_name)
		return

	var avatar := scene.instantiate() as CharacterBody3D
	if not avatar:
		push_error("[WorldManager] La scène n'est pas un CharacterBody3D")
		return

	if spawn_point:
		avatar.global_transform = spawn_point.global_transform
	add_child(avatar)
	print("[WorldManager] Avatar '", model_name, "' spawné à : ",
		spawn_point.global_position if spawn_point else Vector3.ZERO)

func _setup_camera() -> void:
	if use_fps and camera_fps:
		camera_fps.current = true
		if camera_tps:
			camera_tps.current = false
	elif camera_tps:
		camera_tps.current = true
		if camera_fps:
			camera_fps.current = false

# ── FIX CRITIQUE : gravité dans _physics_process, pas _process ────────────────
# FIX CRITIQUE : ne pas appliquer move_and_slide() sur le Player ici,
# il le fait déjà dans son propre _physics_process()
func _physics_process(delta: float) -> void:
	for c in characters:
		# Sauter le Player : il gère lui-même sa physique
		if c.is_in_group("player"):
			continue
		c.velocity.y -= 9.8 * delta
		c.move_and_slide()

	if player_character:
		_update_camera(player_character)

func _update_camera(player: CharacterBody3D) -> void:
	if use_fps and camera_fps:
		var eye_pos := player.global_transform.origin + Vector3(0, 1.6, 0)
		camera_fps.global_transform.origin = eye_pos
		# ── FIX : utiliser global_transform.basis pour la direction ──
		var look_target := eye_pos + (-player.global_transform.basis.z * 10.0)
		camera_fps.look_at(look_target)
	elif camera_tps:
		var cam_offset := Vector3(0, 2.0, 3.5)
		camera_tps.global_transform.origin = player.global_transform.origin + cam_offset
		camera_tps.look_at(player.global_transform.origin + Vector3(0, 1.0, 0))
