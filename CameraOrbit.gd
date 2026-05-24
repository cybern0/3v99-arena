extends Camera

# Paramètres de configuration
@export var look_sensitivity: float = 0.003
@export var min_look_angle: float = -89.0
@export var max_look_angle: float = 89.0
@export var touch_sensitivity: float = 0.005

# Variables internes
var player: Node3D
var mouse_delta: Vector2 = Vector2.ZERO
var touch_start: Vector2 = Vector2.ZERO
var is_touching: bool = false

func _ready() -> void:
	process_mode = PROCESS_MODE_DISABLED
	physics_process_enabled = true
	
	# Récupérer le parent comme joueur (doit être un Node3D)
	if get_parent() is Node3D:
		player = get_parent() as Node3D
	else:
		push_error("CameraOrbit doit être enfant d'un Node3D")
		return

func _physics_process(delta: float) -> void:
	if not player:
		return
	
	# Appliquer la rotation verticale à la caméra
	var rotation_deg = rotation_degrees
	rotation_deg.x -= mouse_delta.y * look_sensitivity * 60.0 * delta
	rotation_deg.x = clamp(rotation_deg.x, min_look_angle, max_look_angle)
	rotation_degrees = rotation_deg
	
	# Appliquer la rotation horizontale au joueur
	var player_rot_deg = player.rotation_degrees
	player_rot_deg.y -= mouse_delta.x * look_sensitivity * 60.0 * delta
	player.rotation_degrees = player_rot_deg
	
	# Réinitialiser le delta
	mouse_delta = Vector2.ZERO

func _input(event: InputEvent) -> void:
	# Gestion souris (pour tests sur desktop)
	if event is InputEventMouseMotion:
		var mouse_motion = event as InputEventMouseMotion
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			mouse_delta = mouse_motion.relative
	
	# Gestion tactile optimisée pour mobile
	elif event is InputEventScreenTouch:
		var touch_event = event as InputEventScreenTouch
		if touch_event.pressed:
			is_touching = true
			touch_start = touch_event.position
		else:
			is_touching = false
	
	elif event is InputEventScreenDrag:
		var drag_event = event as InputEventScreenDrag
		if is_touching:
			# Utiliser la différence de position pour le mouvement tactile
			var touch_delta = drag_event.relative
			mouse_delta = touch_delta * touch_sensitivity * 100.0
