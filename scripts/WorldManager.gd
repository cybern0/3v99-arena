## WorldManager.gd — Gestionnaire de monde (Boss Elimination + Battle Royal)
extends Node3D
class_name WorldManager

signal avatar_spawned(avatar: Node3D)
signal world_ready(world_id: int)
signal multiplayer_spawner_ready(spawner: MultiplayerSpawner)
signal character_registered(character: CharacterBody3D)
signal character_unregistered(character: CharacterBody3D)

@export_group("World")
@export var world_id:         int    = 1
@export var world_scene_name: String = "w_1"

@export_group("Avatar Scenes")
@export var p1_scene: PackedScene
@export var p2_scene: PackedScene

@export_group("Spawner Names")
@export var avatar_spawn_point_path: NodePath  = NodePath("Spawnable")
@export var player_spawner_name:     String    = "MultiplayerSpawner"
@export var boss_spawner_name:       String    = "MultiplayerSpawnerBoss"

@export_group("Legacy Compatibility")
@export var legacy_player_group_name:     String = "player"
@export var legacy_players_group_name:    String = "Characters"
@export var legacy_characters_group_name: String = "characters"
@export var legacy_boss_group_name:       String = "boss"

var characters:        Array[CharacterBody3D] = []
var player_character:  CharacterBody3D        = null
var spawned_avatar:    CharacterBody3D        = null
var camera_tps:        Camera3D               = null
var camera_fps:        Camera3D               = null
var use_fps:           bool                   = false

var _player_spawners: Array[MultiplayerSpawner] = []
var _boss_spawners:   Array[MultiplayerSpawner] = []

@onready var spawn_point: Node3D = get_node_or_null(avatar_spawn_point_path)

# ─────────────────────────────────────────────
#  Initialisation
# ─────────────────────────────────────────────
func _ready() -> void:
	_refresh_scene_links()
	_collect_characters()
	_spawn_selected_avatar()
	_configure_multiplayer_spawners()
	_setup_cameras()
	_bind_scene_entities()    # une seule definition — FIX: doublon supprime
	world_ready.emit(world_id)

func _refresh_scene_links() -> void:
	if spawn_point == null:
		spawn_point = get_node_or_null(avatar_spawn_point_path)
	camera_tps = get_node_or_null("CameraTPS") as Camera3D
	camera_fps = get_node_or_null("CameraFPS") as Camera3D

func _collect_characters() -> void:
	characters.clear()
	var groups := [legacy_characters_group_name, legacy_players_group_name, legacy_player_group_name]
	for group_name in groups:
		for node in get_tree().get_nodes_in_group(group_name):
			if node is CharacterBody3D and not characters.has(node):
				characters.append(node)

	if characters.is_empty():
		for node in get_children():
			if node is CharacterBody3D and not characters.has(node):
				characters.append(node)

	if not characters.is_empty():
		player_character = characters[0]

func _spawn_selected_avatar() -> void:
	var sm         := get_node_or_null("/root/SessionManager")
	var model_name := "Model 1"
	if sm and sm.has_method("get"):
		var _sel = sm.get("selected_model")
		model_name = String(_sel) if _sel != null else "Model 1"

	var scene: PackedScene = p1_scene
	if model_name == "Model 2" and p2_scene:
		scene = p2_scene
	elif not p1_scene and p2_scene:
		scene = p2_scene

	if not scene:
		push_warning("[WorldManager] Aucune scene d'avatar fournie."); return

	if spawned_avatar and is_instance_valid(spawned_avatar):
		return

	var avatar := scene.instantiate()
	if avatar is CharacterBody3D:
		spawned_avatar = avatar
		if spawn_point:
			spawned_avatar.global_transform = spawn_point.global_transform
		add_child(spawned_avatar)
		_register_character_node(spawned_avatar)
		avatar_spawned.emit(spawned_avatar)

func _configure_multiplayer_spawners() -> void:
	_player_spawners.clear()
	_boss_spawners.clear()

	for node in find_children("*", "MultiplayerSpawner", true, false):
		if node is MultiplayerSpawner:
			if String(node.name).to_lower().contains("boss"):
				_boss_spawners.append(node)
			else:
				_player_spawners.append(node)
			multiplayer_spawner_ready.emit(node)

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
	var sm := get_node_or_null("/root/SessionManager")
	if sm and sm.has_method("get"):
		var _sc = sm.get("solo_config")
		var solo_config: Dictionary = _sc if typeof(_sc) == TYPE_DICTIONARY else {}
		if solo_config.has("camera"):
			use_fps = String(solo_config["camera"]) == "FPS"

	if use_fps and camera_fps:
		camera_fps.current = true
		if camera_tps: camera_tps.current = false
	elif camera_tps:
		camera_tps.current = true
		if camera_fps: camera_fps.current = false

# ─────────────────────────────────────────────
#  Liaison entites de scene
# FIX : une seule definition (la precedente etait dupliquee)
# ─────────────────────────────────────────────
func _bind_scene_entities() -> void:
	for node in get_tree().get_nodes_in_group(legacy_player_group_name):
		if node is CharacterBody3D: _register_character_node(node)
	for node in get_tree().get_nodes_in_group(legacy_characters_group_name):
		if node is CharacterBody3D: _register_character_node(node)
	for node in get_tree().get_nodes_in_group(legacy_players_group_name):
		if node is CharacterBody3D: _register_character_node(node)

	for node in get_children():
		if node != self and node.has_method("set_world_manager"):
			node.call("set_world_manager", self)

# ─────────────────────────────────────────────
#  Process
# ─────────────────────────────────────────────
func _process(delta: float) -> void:
	for c in characters:
		if c:
			if not c.is_on_floor():
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

# ─────────────────────────────────────────────
#  Enregistrement personnages
# ─────────────────────────────────────────────
func register_character(character: CharacterBody3D) -> void:
	_register_character_node(character)

func unregister_character(character: CharacterBody3D) -> void:
	if not character: return
	characters.erase(character)
	character_unregistered.emit(character)
	if player_character == character:
		player_character = characters[0] if not characters.is_empty() else null

func _register_character_node(character: CharacterBody3D) -> void:
	if not character: return
	if not characters.has(character):
		characters.append(character)
		character_registered.emit(character)

	if character.is_in_group(legacy_player_group_name) or character.is_in_group(legacy_characters_group_name):
		player_character = character

	if character.has_method("set_world_manager"):
		character.call("set_world_manager", self)
	if character.has_method("set_network_authority_from_world"):
		character.call("set_network_authority_from_world", multiplayer.get_unique_id())

# ─────────────────────────────────────────────
#  API publique
# ─────────────────────────────────────────────
func get_player_character() -> CharacterBody3D:   return player_character
func get_characters() -> Array[CharacterBody3D]:  return characters.duplicate()
func get_player_spawners() -> Array[MultiplayerSpawner]: return _player_spawners.duplicate()
func get_boss_spawners()   -> Array[MultiplayerSpawner]: return _boss_spawners.duplicate()
func get_main_player_spawner() -> MultiplayerSpawner:
	return _player_spawners[0] if not _player_spawners.is_empty() else null
func get_main_boss_spawner() -> MultiplayerSpawner:
	return _boss_spawners[0] if not _boss_spawners.is_empty() else null

func refresh_world_bindings() -> void:
	_refresh_scene_links()
	_collect_characters()
	_configure_multiplayer_spawners()
	_bind_scene_entities()
