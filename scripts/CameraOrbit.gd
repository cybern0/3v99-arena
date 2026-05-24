extends Node3D

@export var look_sensitivity: float = 0.003
@export var min_look_angle:   float = -89.0
@export var max_look_angle:   float = 89.0
@export var touch_sensitivity: float = 0.005

var player: Node3D = null

# ── FIX double-scaling : deux variables séparées ──────────────────────────────
# _mouse_delta : pixels bruts depuis InputEventMouseMotion
# _touch_delta : pixels bruts depuis InputEventScreenDrag (sans pré-scale)
var _mouse_delta: Vector2 = Vector2.ZERO
var _touch_delta: Vector2 = Vector2.ZERO
var _is_touching: bool    = false

func _ready() -> void:
	if get_parent() is Node3D:
		player = get_parent() as Node3D
	else:
		push_error("CameraOrbit doit être enfant d'un Node3D")

func _physics_process(delta: float) -> void:
	if not player:
		return

	# Unifier les deux sources en appliquant leur sensibilité respective
	var combined := _mouse_delta * look_sensitivity + _touch_delta * touch_sensitivity

	# Rotation verticale (caméra)
	var rot := rotation_degrees
	rot.x -= combined.y * 60.0 * delta
	rot.x  = clamp(rot.x, min_look_angle, max_look_angle)
	rotation_degrees = rot

	# Rotation horizontale (joueur)
	var p_rot := player.rotation_degrees
	p_rot.y -= combined.x * 60.0 * delta
	player.rotation_degrees = p_rot

	# Consommer les deltas
	_mouse_delta = Vector2.ZERO
	_touch_delta = Vector2.ZERO

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			_mouse_delta = (event as InputEventMouseMotion).relative

	elif event is InputEventScreenTouch:
		_is_touching = (event as InputEventScreenTouch).pressed

	elif event is InputEventScreenDrag:
		# ── FIX : on stocke les pixels bruts, la sensibilité s'applique dans _physics_process
		if _is_touching:
			_touch_delta = (event as InputEventScreenDrag).relative
