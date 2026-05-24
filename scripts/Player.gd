extends CharacterBody3D
class_name Player

# ─────────────────────────────────────────────
#  Configuration mobile & gameplay
# ─────────────────────────────────────────────
@export_group("Movement")
@export var walk_speed: float = 5.0
@export var run_speed: float = 8.0
@export var acceleration: float = 10.0
@export var friction: float = 8.0
@export var jump_velocity: float = 4.5
@export var gravity: float = 9.8

@export_group("Camera")
@export var camera_sensitivity: float = 0.003
@export var touch_sensitivity: float = 0.005
@export var min_pitch: float = -89.0
@export var max_pitch: float = 89.0

@export_group("Mobile Controls")
@export var enable_mobile_controls: bool = true
@export var joystick_deadzone: float = 0.1

# ─────────────────────────────────────────────
#  Variables internes
# ─────────────────────────────────────────────
var _is_moving: bool = false
var _is_jumping: bool = false
var _input_direction: Vector2 = Vector2.ZERO
var _camera_rotation: Vector2 = Vector2.ZERO
var _touch_id: int = -1
var _touch_start: Vector2 = Vector2.ZERO
var _last_touch_pos: Vector2 = Vector2.ZERO
var _is_touching: bool = false

# Signaux pour l'UI
signal jump_pressed
signal jump_released
signal move_vector_updated(direction: Vector2)
signal player_died

# Reference au CameraOrbit si présent
var _camera_orbit: Node = null

# ─────────────────────────────────────────────
#  Initialisation
# ─────────────────────────────────────────────
func _ready() -> void:
	# Trouver CameraOrbit dans les enfants
	_camera_orbit = find_child("CameraOrbit", true, false)
	
	# Configurer pour mobile si activé
	if enable_mobile_controls and OS.get_name() in ["Android", "iOS"]:
		_setup_mobile_mode()
	
	# Ajouter au groupe Characters
	add_to_group("Characters")
	print("[Player] Initialisé - Mobile: ", enable_mobile_controls)

func _setup_mobile_mode() -> void:
	# Optimisations pour mobile
	Engine.max_fps = 60
	RenderingServer.set_default_texture_filter(CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC)
	print("[Player] Mode mobile activé")

# ─────────────────────────────────────────────
#  Input handling (Desktop + Mobile)
# ─────────────────────────────────────────────
func _unhandled_input(event: InputEvent) -> void:
	if not enable_mobile_controls:
		return
	
	# Gestion tactile pour rotation caméra
	if event is InputEventScreenTouch:
		var touch_event = event as InputEventScreenTouch
		if touch_event.pressed:
			_is_touching = true
			_touch_id = touch_event.index
			_touch_start = touch_event.position
			_last_touch_pos = touch_event.position
		else:
			if touch_event.index == _touch_id:
				_is_touching = false
				_touch_id = -1
	
	elif event is InputEventScreenDrag:
		if _is_touching and event.index == _touch_id:
			var drag_event = event as InputEventScreenDrag
			var delta = drag_event.relative * touch_sensitivity * 100.0
			
			# Rotation horizontale (joueur)
			rotate_y(-delta.x)
			
			# Rotation verticale (caméra)
			if _camera_orbit:
				_camera_orbit.rotation_degrees.x = clamp(
					_camera_orbit.rotation_degrees.x - delta.y,
					min_pitch,
					max_pitch
				)

# ─────────────────────────────────────────────
#  Physics Process
# ─────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	_handle_gravity(delta)
	_handle_movement(delta)
	_handle_jump()
	
	move_and_slide()
	
	# Émettre le signal de direction pour l'UI
	move_vector_updated.emit(_input_direction)

func _handle_gravity(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta

func _handle_movement(delta: float) -> void:
	# Récupérer la direction d'entrée (mobile ou clavier)
	if enable_mobile_controls:
		_input_direction = _get_mobile_input()
	else:
		_input_direction = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	
	# Appliquer la direction relative à la caméra
	var direction := transform.basis * Vector3(_input_direction.x, 0, _input_direction.y)
	
	if direction.length() > 0:
		direction = direction.normalized()
		_is_moving = true
		
		# Déterminer la vitesse (marche ou course)
		var current_speed = run_speed if Input.is_action_pressed("ui_run") else walk_speed
		
		# Accélération
		velocity.x = move_toward(velocity.x, direction.x * current_speed, acceleration * delta)
		velocity.z = move_toward(velocity.z, direction.z * current_speed, acceleration * delta)
	else:
		_is_moving = false
		# Friction
		velocity.x = move_toward(velocity.x, 0, friction * delta)
		velocity.z = move_toward(velocity.z, 0, friction * delta)

func _handle_jump() -> void:
	if is_on_floor():
		_is_jumping = false
		
	# Saut via input ou signal UI
	if (Input.is_action_just_pressed("ui_accept") or _is_jumping) and is_on_floor():
		velocity.y = jump_velocity
		_is_jumping = true

# ─────────────────────────────────────────────
#  Mobile Input
# ─────────────────────────────────────────────
func _get_mobile_input() -> Vector2:
	var ui_manager = get_node_or_null("/root/MainUI")
	if ui_manager and ui_manager.has_method("get_joystick_input"):
		return ui_manager.get_joystick_input()
	return Vector2.ZERO

# ─────────────────────────────────────────────
#  Méthodes publiques pour l'UI
# ─────────────────────────────────────────────
func set_move_input(direction: Vector2) -> void:
	_input_direction = direction

func do_jump() -> void:
	_is_jumping = true

func stop_movement() -> void:
	_input_direction = Vector2.ZERO

# ─────────────────────────────────────────────
#  Combat & Actions (à étendre)
# ─────────────────────────────────────────────
func take_damage(amount: float, attacker: Node = null) -> void:
	# À implémenter avec système de vie
	print("[Player] Dégâts reçus: ", amount)
	if amount >= 100:  # Valeur exemple
		player_died.emit()

func heal(amount: float) -> void:
	# À implémenter
	print("[Player] Soin: ", amount)

# ─────────────────────────────────────────────
#  Utilitaires
# ─────────────────────────────────────────────
func get_is_moving() -> bool:
	return _is_moving

func get_input_direction() -> Vector2:
	return _input_direction
