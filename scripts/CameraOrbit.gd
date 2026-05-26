extends Node3D

@export var look_sensitivity:  float = 0.003
@export var min_look_angle:    float = -89.0
@export var max_look_angle:    float = 89.0
@export var touch_sensitivity: float = 0.005

var player: Node3D = null

# ── Mobile seulement : accumulation du delta tactile traité dans _physics_process
# ── PC       : rotation appliquée directement dans _input (pas de delta accumulé)
var _touch_delta: Vector2 = Vector2.ZERO
var _is_touching: bool    = false

func _ready() -> void:
	if get_parent() is Node3D:
		player = get_parent() as Node3D
	else:
		push_error("CameraOrbit doit être enfant d'un Node3D")

# ──────────────────────────────────────────────────────────────────────────────
#  Physics process — MOBILE uniquement
#  Le PC est géré dans _input() directement pour une réactivité maximale.
# ──────────────────────────────────────────────────────────────────────────────
func _physics_process(_delta: float) -> void:
	if not player:
		return

	# Touch (mobile) — delta accumulé depuis _input
	if _touch_delta != Vector2.ZERO:
		# Rotation verticale caméra
		var rot := rotation_degrees
		rot.x -= _touch_delta.y * touch_sensitivity * 100.0
		rot.x  = clamp(rot.x, min_look_angle, max_look_angle)
		rotation_degrees = rot

		# Rotation horizontale joueur
		# Trigonométrie : la rotation Y du joueur détermine forward/right
		# (les vecteurs sin/cos sont recalculés par Player._handle_movement)
		var p_rot := player.rotation_degrees
		p_rot.y -= _touch_delta.x * touch_sensitivity * 100.0
		player.rotation_degrees = p_rot

		_touch_delta = Vector2.ZERO

# ──────────────────────────────────────────────────────────────────────────────
#  Input
# ──────────────────────────────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:

	# ── PC : souris — rotation IMMÉDIATE sans multiplier par delta
	# ─────────────────────────────────────────────────────────────────────────
	# Avantages :
	#   • Réactivité identique quel que soit le FPS (pas de scaling par delta)
	#   • Un pixel de souris = look_sensitivity radians, constant
	#   • Pas de latence d'un frame sur la rotation
	#
	# Trigonométrie : player.rotation.y est l'angle (radians) autour de Y.
	# Player._handle_movement() utilise sin/cos de cet angle pour calculer
	# forward/right → le joueur avance toujours dans la direction qu'il regarde.
	# ─────────────────────────────────────────────────────────────────────────
	if event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion

		# Pitch (caméra haut/bas)
		var new_pitch: float = rotation_degrees.x - motion.relative.y * look_sensitivity * (180.0 / PI)
		rotation_degrees.x = clamp(new_pitch, min_look_angle, max_look_angle)

		# Yaw (joueur gauche/droite) — modifie rotation.y du CharacterBody3D
		# → sin(rotation.y) et cos(rotation.y) dans Player._handle_movement
		#   calculeront automatiquement la bonne direction forward/right
		if player:
			player.rotation.y -= motion.relative.x * look_sensitivity

	# ── Mobile : touch — INCHANGÉ par rapport à la version précédente ────────
	elif event is InputEventScreenTouch:
		_is_touching = (event as InputEventScreenTouch).pressed

	elif event is InputEventScreenDrag:
		# Stocke les pixels bruts ; la sensibilité s'applique dans _physics_process
		if _is_touching:
			_touch_delta = (event as InputEventScreenDrag).relative
