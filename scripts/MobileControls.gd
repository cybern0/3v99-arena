extends CanvasLayer
class_name MobileControls

# ─────────────────────────────────────────────
#  Configuration
# ─────────────────────────────────────────────
@export var joystick_sensitivity: float = 1.0
@export var deadzone: float = 0.1
@export var show_controls_on_mobile_only: bool = true

# ─────────────────────────────────────────────
#  Noeuds UI
# ─────────────────────────────────────────────
@onready var joystick_container: Control = $JoystickContainer
@onready var joystick_knob: Control = $JoystickContainer/JoystickKnob
@onready var action_buttons: Control = $ActionButtons
@onready var jump_button: Button = $ActionButtons/JumpButton
@onready var run_button: Button = $ActionButtons/RunButton
@onready var crouch_button: Button = $ActionButtons/CrouchButton

# ─────────────────────────────────────────────
#  État
# ─────────────────────────────────────────────
var _joystick_center: Vector2 = Vector2.ZERO
var _joystick_current: Vector2 = Vector2.ZERO
var _is_joystick_pressed: bool = false
var _touch_id: int = -1
var _max_radius: float = 50.0

# Signaux
signal move_input(direction: Vector2)
signal jump_pressed
signal jump_released
signal run_pressed
signal run_released
signal crouch_pressed
signal crouch_released

# ─────────────────────────────────────────────
#  Initialisation
# ─────────────────────────────────────────────
func _ready() -> void:
	# Masquer si non mobile et option activée
	if show_controls_on_mobile_only and OS.get_name() not in ["Android", "iOS"]:
		visible = false
		return
	
	# Configurer le joystick
	if joystick_container:
		_max_radius = joystick_container.size.x / 2.0
		_joystick_center = joystick_container.size / 2.0
	
	# Connexion des boutons
	_connect_buttons()
	
	print("[MobileControls] Initialisé - Visible: ", visible)

func _connect_buttons() -> void:
	if jump_button:
		jump_button.pressed.connect(_on_jump_pressed)
		jump_button.released.connect(_on_jump_released)
	
	if run_button:
		run_button.pressed.connect(_on_run_pressed)
		run_button.released.connect(_on_run_released)
	
	if crouch_button:
		crouch_button.pressed.connect(_on_crouch_pressed)
		crouch_button.released.connect(_on_crouch_released)

# ─────────────────────────────────────────────
#  Input Tactile
# ─────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if not visible:
		return
	
	# Gestion du joystick tactile
	if event is InputEventScreenTouch:
		var touch_event = event as InputEventScreenTouch
		var touch_pos = touch_event.position
		
		# Vérifier si le touch est dans la zone du joystick
		if _is_in_joystick_zone(touch_pos):
			if touch_event.pressed:
				_is_joystick_pressed = true
				_touch_id = touch_event.index
				_update_joystick(touch_pos)
			else:
				if touch_event.index == _touch_id:
					_is_joystick_pressed = false
					_touch_id = -1
					_reset_joystick()
	
	elif event is InputEventScreenDrag:
		if _is_joystick_pressed and event.index == _touch_id:
			var drag_event = event as InputEventScreenDrag
			_update_joystick(drag_event.position)

func _is_in_joystick_zone(pos: Vector2) -> bool:
	if not joystick_container:
		return false
	
	var container_rect = Rect2(
		joystick_container.global_position,
		joystick_container.size
	)
	# Étendre la zone de détection
	container_rect = container_rect.grow(100)
	return container_rect.has_point(pos)

func _update_joystick(touch_pos: Vector2) -> void:
	if not joystick_knob or not joystick_container:
		return
	
	# Position relative au centre du joystick
	var local_pos = touch_pos - joystick_container.global_position
	var direction = (local_pos - _joystick_center).normalized()
	var distance = min(local_pos.distance_to(_joystick_center), _max_radius)
	
	# Déplacer le knob
	var new_pos = _joystick_center + direction * distance
	joystick_knob.position = new_pos
	
	# Calculer l'entrée normalisée (-1 à 1)
	var normalized_distance = distance / _max_radius
	if normalized_distance < deadzone:
		_joystick_current = Vector2.ZERO
	else:
		_joystick_current = direction * ((normalized_distance - deadzone) / (1.0 - deadzone))
	
	# Émettre le signal
	move_input.emit(_joystick_current * joystick_sensitivity)

func _reset_joystick() -> void:
	if joystick_knob:
		joystick_knob.position = _joystick_center
	_joystick_current = Vector2.ZERO
	move_input.emit(Vector2.ZERO)

# ─────────────────────────────────────────────
#  Handlers des boutons
# ─────────────────────────────────────────────
func _on_jump_pressed() -> void:
	jump_pressed.emit()

func _on_jump_released() -> void:
	jump_released.emit()

func _on_run_pressed() -> void:
	run_pressed.emit()
	Input.action_press("ui_run")

func _on_run_released() -> void:
	run_released.emit()
	Input.action_release("ui_run")

func _on_crouch_pressed() -> void:
	crouch_pressed.emit()

func _on_crouch_released() -> void:
	crouch_released.emit()

# ─────────────────────────────────────────────
#  Méthodes publiques
# ─────────────────────────────────────────────
func get_joystick_input() -> Vector2:
	return _joystick_current * joystick_sensitivity

func set_sensitivity(value: float) -> void:
	joystick_sensitivity = clamp(value, 0.1, 2.0)

func set_deadzone(value: float) -> void:
	deadzone = clamp(value, 0.0, 0.5)

func show_controls(show: bool) -> void:
	visible = show

func toggle_controls() -> void:
	visible = !visible

# ─────────────────────────────────────────────
#  Utilitaires
# ─────────────────────────────────────────────
func _process(_delta: float) -> void:
	# Animation subtile du joystick quand inactif
	if not _is_joystick_pressed and joystick_knob:
		var current_pos = joystick_knob.position
		var target_pos = _joystick_center
		joystick_knob.position = current_pos.lerp(target_pos, 0.2)
