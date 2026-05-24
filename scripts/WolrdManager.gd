extends Node3D

var characters: Array[CharacterBody3D] = []
var player_character: CharacterBody3D = null
var camera_tps: Camera3D = null
var camera_fps: Camera3D = null
var use_fps: bool = false

# Reference au noeud Spawnable pour le point de spawn
@onready var spawn_point: Node3D = $Spawnable

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# Spawn de l'avatar choisi depuis SessionManager
	_spawn_selected_avatar()
	
	var chars = get_tree().get_nodes_in_group("Characters")
	characters.clear()
	for c in chars:
		if c is CharacterBody3D:
			characters.append(c)
	
	# Trouver le joueur (premier personnage ou celui marque comme joueur)
	if characters.size() > 0:
		player_character = characters[0]
	
	# Recuperer les cameras si elles existent
	camera_tps = $CameraTPS if has_node("CameraTPS") else null
	camera_fps = $CameraFPS if has_node("CameraFPS") else null
	
	# Configurer la camera selon le mode choisi
	_setup_camera()
	
	# Recuperer la config du SessionManager
	if has_node("/root/SessionManager"):
		var sm = get_node("/root/SessionManager")
		if sm.solo_config.has("camera"):
			use_fps = (sm.solo_config["camera"] == "FPS")
		_setup_camera()

func _spawn_selected_avatar() -> void:
	# Recupere le modele selectionne depuis SessionManager
	var sm = get_node_or_null("/root/SessionManager")
	if not sm:
		push_warning("[WorldManager] SessionManager non trouve, utilisation du modele par defaut")
		return
	
	var model_name: String = sm.selected_model if sm.selected_model else "Model 1"
	
	# Charger la scene du modele
	var MODEL_SCENES := {
		"Model 1": preload("res://scenes/P1.tscn"),
		"Model 2": preload("res://scenes/P2.tscn"),
	}
	
	if not MODEL_SCENES.has(model_name):
		model_name = "Model 1"
	
	var scene: PackedScene = MODEL_SCENES[model_name] as PackedScene
	if not scene:
		push_error("[WorldManager] Scene du modele introuvable: " + model_name)
		return
	
	# Instancier l'avatar au point de spawn
	var avatar: CharacterBody3D = scene.instantiate() as CharacterBody3D
	if avatar and spawn_point:
		avatar.global_transform = spawn_point.global_transform
		add_child(avatar)
		print("[WorldManager] Avatar '", model_name, "' spawn a la position de Spawnable: ", spawn_point.global_position)
	elif avatar:
		add_child(avatar)
		print("[WorldManager] Avatar '", model_name, "' spawn (point Spawnable non trouve)")

func _setup_camera() -> void:
	if use_fps and camera_fps:
		camera_fps.current = true
		if camera_tps:
			camera_tps.current = false
	elif camera_tps:
		camera_tps.current = true
		if camera_fps:
			camera_fps.current = false

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	for c in characters:
		c.velocity.y -= 9.8 * delta
		c.move_and_slide()
	
	# Mettre a jour la camera pour suivre le joueur
	if player_character:
		_update_camera(player_character)

func _update_camera(player: CharacterBody3D) -> void:
	if use_fps and camera_fps:
		# Mode FPS: camera positionnee au niveau des yeux
		var eye_offset := Vector3(0, 1.6, 0.3)
		camera_fps.global_transform.origin = player.global_transform.origin + eye_offset
		camera_fps.look_at(player.global_transform.origin + player.transform.basis.z * -10 + Vector3(0, 1.6, 0))
	elif camera_tps:
		# Mode TPS: camera derriere le joueur
		var cam_offset := Vector3(0, 2.0, 3.5)
		camera_tps.global_transform.origin = player.global_transform.origin + cam_offset
		camera_tps.look_at(player.global_transform.origin + Vector3(0, 1.0, 0))
