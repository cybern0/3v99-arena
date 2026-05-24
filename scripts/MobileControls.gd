extends CanvasLayer
class_name MobileControls

@export var joystick_sensitivity:        float = 1.0
@export var deadzone:                    float = 0.1
@export var show_controls_on_mobile_only: bool = true

@onready var joystick_container: Control = $JoystickContainer
@onready var joystick_knob:      Control = $JoystickContainer/JoystickKnob
@onready var action_buttons:     Control = $ActionButtons
@onready var jump_button:        Button  = $ActionButtons/JumpButton
@onready var run_button:         Button  = $ActionButtons/RunButton
@onready var crouch_button:      Button  = $ActionButtons/CrouchButton

var _joystick_center:     Vector2 = Vector2.ZERO
var _joystick_current:    Vector2 = Vector2.ZERO
var _is_joystick_pressed: bool    = false
var _touch_id:            int     = -1
var _max_radius:          float   = 50.0

signal move_input(direction: Vector2)
signal jump_pressed
signal jump_released
signal run_pressed
signal run_released
signal crouch_pressed
signal crouch_released

func _ready() -> void:
	if show_controls_on_mobile_only and OS.get_name() not in ["Android", "iOS"]:
		visible = false
		return

	# ── FIX : attendre un frame pour que le layout soit calculé ──────────────
	await get_tree().process_frame

	if joystick_container:
		_max_radius    = joystick_container.size.x / 2.0
		_joystick_center = joystick_container.size / 2.0
		if joystick_knob:
			joystick_knob.position = _joystick_center

	_connect_buttons()
	print("[MobileControls] Initialisé — visible : ", visible)

func _connect_buttons() -> void:
	# ── FIX : "released" n'existe pas en Godot 4 → utiliser "button_up" ──────
	if jump_button:
		jump_button.pressed.connect(_on_jump_pressed)
		jump_button.button_up.connect(_on_jump_released)

	if run_button:
		run_button.pressed.connect(_on_run_pressed)
		run_button.button_up.connect(_on_run_released)

	if crouch_button:
		crouch_button.pressed.connect(_on_crouch_pressed)
		crouch_button.button_up.connect(_on_crouch_released)

# ─────────────────────────────────────────────
#  Input Tactile
# ─────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if not visible:
		return

	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if _is_in_joystick_zone(touch.position):
			if touch.pressed:
				_is_joystick_pressed = true
				_touch_id = touch.index
				_update_joystick(touch.position)
			elif touch.index == _touch_id:
				_is_joystick_pressed = false
				_touch_id = -1
				_reset_joystick()

	elif event is InputEventScreenDrag:
		if _is_joystick_pressed and event.index == _touch_id:
			_update_joystick((event as InputEventScreenDrag).position)

func _is_in_joystick_zone(pos: Vector2) -> bool:
	if not joystick_container:
		return false
	return Rect2(joystick_container.global_position, joystick_container.size).grow(100).has_point(pos)

func _update_joystick(touch_pos: Vector2) -> void:
	if not joystick_knob or not joystick_container:
		return
	var local_pos  := touch_pos - joystick_container.global_position
	var direction  := (local_pos - _joystick_center).normalized()
	var distance   := minf(local_pos.distance_to(_joystick_center), _max_radius)
	joystick_knob.position = _joystick_center + direction * distance
	var norm := distance / _max_radius
	_joystick_current = Vector2.ZERO if norm < deadzone else direction * ((norm - deadzone) / (1.0 - deadzone))
	move_input.emit(_joystick_current * joystick_sensitivity)

func _reset_joystick() -> void:
	if joystick_knob:
		joystick_knob.position = _joystick_center
	_joystick_current = Vector2.ZERO
	move_input.emit(Vector2.ZERO)

# ─────────────────────────────────────────────
#  Handlers boutons
# ─────────────────────────────────────────────
func _on_jump_pressed()   -> void: jump_pressed.emit()
func _on_jump_released()  -> void: jump_released.emit()

func _on_run_pressed()    -> void:
	run_pressed.emit()
	Input.action_press("ui_run")

func _on_run_released()   -> void:
	run_released.emit()
	Input.action_release("ui_run")

func _on_crouch_pressed()  -> void: crouch_pressed.emit()
func _on_crouch_released() -> void: crouch_released.emit()

# ─────────────────────────────────────────────
#  API publique
# ─────────────────────────────────────────────
func get_joystick_input() -> Vector2: return _joystick_current * joystick_sensitivity
func set_sensitivity(v: float) -> void: joystick_sensitivity = clamp(v, 0.1, 2.0)
func set_deadzone(v: float)    -> void: deadzone = clamp(v, 0.0, 0.5)
func show_controls(show: bool) -> void: visible = show
func toggle_controls()         -> void: visible = !visible

func _process(_delta: float) -> void:
	if not _is_joystick_pressed and joystick_knob:
		joystick_knob.position = joystick_knob.position.lerp(_joystick_center, 0.2)
