extends Node3D
class_name WorldManager

signal avatar_spawned(avatar: Node3D)
signal world_ready(world_id: int)
signal multiplayer_spawner_ready(spawner: MultiplayerSpawner)

@export_group("World")
@export var world_id: int = 1
@export var world_scene_name: String = "w_1"

@export_group("Avatar Scenes")
@export var p1_scene: PackedScene
@export var p2_scene: PackedScene

@export_group("Spawner Names")
@export var avatar_spawn_point_path: NodePath = NodePath("Spawnable")
@export var player_spawner_name: String = "MultiplayerSpawner"
@export var boss_spawner_name: String = "MultiplayerSpawnerBoss"

var characters: Array[CharacterBody3D] = []
var player_character: CharacterBody3D = null
var spawned_avatar: CharacterBody3D = null
var camera_tps: Camera3D = null
var camera_fps: Camera3D = null
var use_fps: bool = false

var _player_spawners: Array[MultiplayerSpawner] = []
var _boss_spawners: Array[MultiplayerSpawner] = []

@onready var spawn_point: Node3D = get_node_or_null(avatar_spawn_point_path)

func _ready() -> void:
	_collect_characters()
	_spawn_selected_avatar()
	_configure_multiplayer_spawners()
	_setup_cameras()
	world_ready.emit(world_id)

func _collect_characters() -> void:
	characters.clear()
	for node in get_tree().get_nodes_in_group("characters"):
		if node is CharacterBody3D:
			characters.append(node)

	if characters.is_empty():
		for node in get_tree().get_nodes_in_group("player"):
			if node is CharacterBody3D:
				characters.append(node)

	if not characters.is_empty():
		player_character = characters[0]

func _spawn_selected_avatar() -> void:
	var sm := get_node_or_null("/root/SessionManager")
	var model_name := "Model 1"
	if sm and sm.has_method("get"):
		model_name = String(sm.get("selected_model", "Model 1"))

	var scene: PackedScene = p1_scene
	if model_name == "Model 2" and p2_scene:
		scene = p2_scene
	elif not p1_scene and p2_scene:
		scene = p2_scene

	if not scene:
		push_warning("[WorldManager] Aucune scène d'avatar fournie.")
		return

	var avatar := scene.instantiate()
	if avatar is CharacterBody3D:
		spawned_avatar = avatar
		if spawn_point:
			spawned_avatar.global_transform = spawn_point.global_transform
		add_child(spawned_avatar)
		spawned_avatar.add_to_group("player")
		spawned_avatar.add_to_group("characters")
		player_character = spawned_avatar
		characters = [spawned_avatar]
		avatar_spawned.emit(spawned_avatar)

func _configure_multiplayer_spawners() -> void:
	_player_spawners.clear()
	_boss_spawners.clear()

	for node in find_children("*", "MultiplayerSpawner", true, false):
		if node is MultiplayerSpawner:
			_player_spawners.append(node)
			multiplayer_spawner_ready.emit(node)

	for node in find_children("*", "MultiplayerSpawner", true, false):
		if node is MultiplayerSpawner and String(node.name).to_lower().contains("boss"):
			_boss_spawners.append(node)

	# Les spawners sont souvent configurés dans la scène; ici on ne force pas leur setup,
	# on laisse la scène w_1 / w_2 / w_3 fournir les paths et on synchronise les références.
	if _player_spawners.is_empty():
		var fallback := find_child(player_spawner_name, true, false)
		if fallback is MultiplayerSpawner:
			_player_spawners.append(fallback)
			multiplayer_spawner_ready.emit(fallback)

	if _boss_spawners.is_empty():
		var boss_fallback := find_child(boss_spawner_name, true, false)
		if boss_fallback is MultiplayerSpawner:
			_boss_spawners.append(boss_fallback)

func _setup_cameras() -> void:
	camera_tps = get_node_or_null("CameraTPS") as Camera3D
	camera_fps = get_node_or_null("CameraFPS") as Camera3D

	var sm := get_node_or_null("/root/SessionManager")
	if sm and sm.has_method("get"):
		var solo_config = sm.get("solo_config", {})
		if typeof(solo_config) == TYPE_DICTIONARY and solo_config.has("camera"):
			use_fps = String(solo_config["camera"]) == "FPS"

	if use_fps and camera_fps:
		camera_fps.current = true
		if camera_tps:
			camera_tps.current = false
	elif camera_tps:
		camera_tps.current = true
		if camera_fps:
			camera_fps.current = false

func _process(delta: float) -> void:
	for c in characters:
		if c:
			c.velocity.y -= 9.8 * delta
			c.move_and_slide()

	if player_character:
		_update_camera(player_character)

func _update_camera(player: CharacterBody3D) -> void:
	if use_fps and camera_fps:
		var eye_offset := Vector3(0, 1.6, 0.3)
		camera_fps.global_transform.origin = player.global_transform.origin + eye_offset
		camera_fps.look_at(player.global_transform.origin + player.transform.basis.z * -10 + Vector3(0, 1.6, 0))
	elif camera_tps:
		var cam_offset := Vector3(0, 2.0, 3.5)
		camera_tps.global_transform.origin = player.global_transform.origin + cam_offset
		camera_tps.look_at(player.global_transform.origin + Vector3(0, 1.0, 0))

func register_character(character: CharacterBody3D) -> void:
	if character == null:
		return
	if not characters.has(character):
		characters.append(character)
	if character.is_in_group("player"):
		player_character = character

func unregister_character(character: CharacterBody3D) -> void:
	if character == null:
		return
	characters.erase(character)
	if player_character == character:
		player_character = characters[0] if not characters.is_empty() else null

func get_player_character() -> CharacterBody3D:
	return player_character

func get_characters() -> Array[CharacterBody3D]:
	return characters.duplicate()
