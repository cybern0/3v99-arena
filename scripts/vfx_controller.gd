# ============================================================
# VFXController — 3v99-arena
# Attach as a child Node of your character root.
# Set `character_type` in the Inspector: "p1","p2","h1","h2","h3"
#
# Hierarchy expected:
#   CharacterBody3D / Node3D  (root)
#   ├── Skeleton3D
#   │   └── MeshInstance3D   (auto-detected)
#   ├── AnimationPlayer      (auto-detected)
#   └── VFXController  ← this script
#       └── VFXParticles     (instance of res://vfx/particles/<id>_particles.tscn)
#           ├── Idle   (GPUParticles3D)
#           ├── Action (GPUParticles3D)
#           └── Die    (GPUParticles3D)
# ============================================================
class_name VFXController
extends Node

# ---- Exports -----------------------------------------------
@export_enum("p1","p2","h1","h2","h3") var character_type: String = "p1"

# ---- Internal refs -----------------------------------------
var _meshes:       Array[MeshInstance3D] = []
var _anim_player:  AnimationPlayer       = null
var _overlay_mat:  ShaderMaterial        = null
var _die_shader:   Shader                = null
var _die_mats:     Array[ShaderMaterial] = []
var _orig_mats:    Dictionary            = {}   # mesh → [Array of mats]
var _tween:        Tween                 = null

var _p_idle:   GPUParticles3D = null
var _p_action: GPUParticles3D = null
var _p_die:    GPUParticles3D = null

# ---- Ready -------------------------------------------------
func _ready() -> void:
	_collect_meshes(get_parent())
	_anim_player = _find_typed(get_parent(), "AnimationPlayer")
	_load_shaders()
	_cache_original_materials()
	_connect_signals()
	_p_idle   = get_node_or_null("VFXParticles/Idle")
	_p_action = get_node_or_null("VFXParticles/Action")
	_p_die    = get_node_or_null("VFXParticles/Die")
	_apply_overlay()
	_set_state(0, 0.0)   # idle, no intensity yet


# ---- Node search helpers -----------------------------------
func _collect_meshes(root: Node) -> void:
	if root is MeshInstance3D:
		_meshes.append(root)
	for c in root.get_children():
		_collect_meshes(c)

func _find_typed(root: Node, class_name_str: String) -> Node:
	if root.get_class() == class_name_str:
		return root
	for c in root.get_children():
		var r = _find_typed(c, class_name_str)
		if r:
			return r
	return null


# ---- Material loading & caching ----------------------------
func _load_shaders() -> void:
	var overlay_path := "res://vfx/characters/%s_vfx.gdshader" % character_type
	var die_path     := "res://vfx/characters/shared_die.gdshader"
	if ResourceLoader.exists(overlay_path):
		_overlay_mat          = ShaderMaterial.new()
		_overlay_mat.shader   = load(overlay_path)
	else:
		push_warning("VFXController: overlay shader not found at " + overlay_path)
	if ResourceLoader.exists(die_path):
		_die_shader = load(die_path)
	else:
		push_warning("VFXController: die shader not found at " + die_path)

func _cache_original_materials() -> void:
	for mesh in _meshes:
		var mats: Array = []
		for i in mesh.get_surface_override_material_count():
			var ov := mesh.get_surface_override_material(i)
			var base := mesh.mesh.surface_get_material(i) if mesh.mesh else null
			mats.append(ov if ov else base)
		_orig_mats[mesh] = mats

func _apply_overlay() -> void:
	if not _overlay_mat:
		return
	for mesh in _meshes:
		mesh.material_overlay = _overlay_mat


# ---- Signal connection -------------------------------------
func _connect_signals() -> void:
	if _anim_player:
		_anim_player.animation_started.connect(_on_anim_started)
		_anim_player.animation_finished.connect(_on_anim_finished)


# ---- Animation callbacks -----------------------------------
func _on_anim_started(anim: StringName) -> void:
	_cancel_tween()
	match anim:
		"idle":            _do_idle()
		"run":             _do_run()
		"punch":           _do_attack(1)
		"kick":            _do_attack(3)
		"jump":            _do_jump()
		"react":           _do_react()
		"die":             _do_die()

func _on_anim_finished(anim: StringName) -> void:
	match anim:
		"punch","kick","jump","react":
			_fade_out(0.35)


# ---- VFX states --------------------------------------------
func _do_idle() -> void:
	_set_state(0, 0.0)
	_fade_in(0.3, 1.0)
	_particles_mode(true, false, false)

func _do_run() -> void:
	_set_state(2, 0.0)
	_fade_in(0.2, 0.9)
	_particles_mode(false, true, false)

func _do_attack(state: int) -> void:
	_set_state(state, 0.0)
	_fade_in(0.06, 1.0)
	if _p_action:
		_p_action.restart()

func _do_jump() -> void:
	_set_state(4, 0.0)
	_fade_in(0.12, 0.8)

func _do_react() -> void:
	_set_state(5, 0.0)
	_fade_in(0.04, 1.0)

func _do_die() -> void:
	_set_state(6, 0.0)
	_particles_mode(false, false, true)
	if not _die_shader:
		return
	# Build per-surface dissolve materials (copy albedo from original)
	_die_mats.clear()
	for mesh in _meshes:
		var orig_list: Array = _orig_mats.get(mesh, [])
		for i in mesh.get_surface_override_material_count():
			var dm := ShaderMaterial.new()
			dm.shader = _die_shader
			var orig = orig_list[i] if i < orig_list.size() else null
			if orig is StandardMaterial3D:
				dm.set_shader_parameter("albedo_texture", orig.albedo_texture)
				dm.set_shader_parameter("base_color",     orig.albedo_color)
			elif orig is ShaderMaterial:
				var t = orig.get_shader_parameter("albedo_texture")
				if t: dm.set_shader_parameter("albedo_texture", t)
			_die_mats.append(dm)
			mesh.set_surface_override_material(i, dm)
	# Animate dissolve 0→1 over 2 s
	_tween = create_tween()
	_tween.tween_method(_set_dissolve_all, 0.0, 1.0, 2.0)

func _restore_materials() -> void:
	for mesh in _meshes:
		var orig_list: Array = _orig_mats.get(mesh, [])
		for i in range(orig_list.size()):
			mesh.set_surface_override_material(i, orig_list[i])
	_die_mats.clear()


# ---- Overlay param helpers ---------------------------------
func _set_state(state: int, intensity: float) -> void:
	if _overlay_mat:
		_overlay_mat.set_shader_parameter("anim_state",    state)
		_overlay_mat.set_shader_parameter("vfx_intensity", intensity)

func _fade_in(dur: float, target: float) -> void:
	_tween = create_tween()
	_tween.tween_method(
		func(v: float): if _overlay_mat: _overlay_mat.set_shader_parameter("vfx_intensity", v),
		0.0, target, dur)

func _fade_out(dur: float) -> void:
	_tween = create_tween()
	_tween.tween_method(
		func(v: float): if _overlay_mat: _overlay_mat.set_shader_parameter("vfx_intensity", v),
		_overlay_mat.get_shader_parameter("vfx_intensity") if _overlay_mat else 1.0, 0.0, dur)
	_tween.tween_callback(func(): _set_state(0, 0.0))

func _set_dissolve_all(v: float) -> void:
	for dm in _die_mats:
		dm.set_shader_parameter("dissolve_amount", v)

func _cancel_tween() -> void:
	if _tween and _tween.is_running():
		_tween.kill()


# ---- Particle helpers --------------------------------------
func _particles_mode(idle: bool, action: bool, die: bool) -> void:
	if _p_idle:   _p_idle.emitting   = idle
	if _p_action: _p_action.emitting = action
	if _p_die:    _p_die.emitting    = die
