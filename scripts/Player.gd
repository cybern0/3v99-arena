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
# La gravité est gérée par WorldManager.gd

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
var _is_running: bool = false
var _is_attacking: bool = false

# Signaux pour l'UI
signal jump_pressed
signal jump_released
signal move_vector_updated(direction: Vector2)
signal player_died
signal attack_requested(attack_type: String)
signal state_changed(new_state: String)

# Reference au CameraOrbit si présent
var _camera_orbit: Node = null
var _animation_player: AnimationPlayer = null
var _canvas_layer: CanvasLayer = null
var _game_hud: GameHUD = null

# État actuel de l'animation
var _current_state: String = "idle"

# ─────────────────────────────────────────────
#  Initialisation
# ─────────────────────────────────────────────
func _ready() -> void:
	# Trouver CameraOrbit dans les enfants
	_camera_orbit = find_child("CameraOrbit", true, false)
	
	# Trouver AnimationPlayer
	_animation_player = find_child("AnimationPlayer", true, false)
	
	# Créer CanvasLayer et GameHUD si besoin
	_create_mobile_controls()
	
	# Configurer pour mobile si activé
	if enable_mobile_controls and OS.get_name() in ["Android", "iOS"]:
		_setup_mobile_mode()
	
	# Ajouter au groupe Characters
	add_to_group("Characters")
	print("[Player] Initialisé - Mobile: ", enable_mobile_controls)

func _create_mobile_controls() -> void:
	# Vérifier si CanvasLayer existe déjà
	_canvas_layer = find_child("CanvasLayer", true, false)
	
	if not _canvas_layer:
		# Charger le CanvasLayer depuis la scene prefabriquee
		var canvas_scene := preload("res://scenes/CanvasLayer.tscn") as PackedScene
		if canvas_scene:
			_canvas_layer = canvas_scene.instantiate() as CanvasLayer
			_canvas_layer.name = "CanvasLayer"
			add_child(_canvas_layer)
			_game_hud = _canvas_layer.find_child("GameHUD", true, false) as GameHUD
			print("[Player] CanvasLayer et GameHUD instancies depuis la scene")
		else:
			push_error("[Player] Impossible de charger CanvasLayer.tscn")
	else:
		# Récupérer GameHUD existant
		_game_hud = _canvas_layer.find_child("GameHUD", true, false) as GameHUD

func _create_mobile_buttons() -> void:
	if not _canvas_layer:
		return
	
	# Container principal pour les boutons d'action
	var actions_container = Control.new()
	actions_container.name = "ActionsContainer"
	actions_container.anchor_left = 0.7
	actions_container.anchor_top = 0.6
	actions_container.anchor_right = 1.0
	actions_container.anchor_bottom = 1.0
	_canvas_layer.add_child(actions_container)
	
	# Bouton Jump
	var jump_btn = Button.new()
	jump_btn.name = "JumpButton"
	jump_btn.text = "⬆"
	jump_btn.position = Vector2(20, 100)
	jump_btn.size = Vector2(80, 80)
	jump_btn.connect("pressed", _on_jump_pressed)
	actions_container.add_child(jump_btn)
	
	# Bouton Punch
	var punch_btn = Button.new()
	punch_btn.name = "PunchButton"
	punch_btn.text = "👊"
	punch_btn.position = Vector2(120, 140)
	punch_btn.size = Vector2(70, 70)
	punch_btn.connect("pressed", _on_punch_pressed)
	actions_container.add_child(punch_btn)
	
	# Bouton Kick
	var kick_btn = Button.new()
	kick_btn.name = "KickButton"
	kick_btn.text = "🦶"
	kick_btn.position = Vector2(200, 140)
	kick_btn.size = Vector2(70, 70)
	kick_btn.connect("pressed", _on_kick_pressed)
	actions_container.add_child(kick_btn)
	
	# Bouton Run (toggle)
	var run_btn = Button.new()
	run_btn.name = "RunButton"
	run_btn.text = "🏃"
	run_btn.position = Vector2(120, 40)
	run_btn.size = Vector2(70, 50)
	run_btn.toggle_mode = true
	run_btn.connect("toggled", _on_run_toggled)
	actions_container.add_child(run_btn)

func _setup_mobile_mode() -> void:
	# Optimisations pour mobile
	Engine.max_fps = 60
	print("[Player] Mode mobile activé")

# ─────────────────────────────────────────────
#  Gestion des animations
# ─────────────────────────────────────────────
func _play_animation(anim_name: String) -> void:
	if not _animation_player:
		return
	
	var available_anims: Array = _animation_player.get_animation_list()
	
	# Vérifier si l'animation existe
	if anim_name in available_anims:
		# Ne pas rejouer la même animation (sauf pour les attaques)
		if _current_state == anim_name and anim_name != "punch" and anim_name != "kick":
			return
		
		_animation_player.play(anim_name)
		_current_state = anim_name
		state_changed.emit(_current_state)

func _update_animation() -> void:
	if not _animation_player:
		return
	
	# Déterminer l'état actuel
	if _is_attacking:
		return  # Laisser l'animation d'attaque se terminer
	
	if not is_on_floor():
		_play_animation("jump")
	elif _input_direction.length() > 0:
		_play_animation("run")
	else:
		_play_animation("idle")

# ─────────────────────────────────────────────
#  Gestionnaires de boutons mobile
# ─────────────────────────────────────────────
func _on_jump_pressed() -> void:
	do_jump()
	jump_pressed.emit()

func _on_punch_pressed() -> void:
	_perform_attack("punch")

func _on_kick_pressed() -> void:
	_perform_attack("kick")

func _on_run_toggled(toggled_on: bool) -> void:
	_is_running = toggled_on

func _perform_attack(attack_type: String) -> void:
	if not _animation_player:
		return
	
	var available_anims: Array = _animation_player.get_animation_list()
	
	if attack_type in available_anims:
		_is_attacking = true
		_animation_player.play(attack_type)
		_current_state = attack_type
		attack_requested.emit(attack_type)
		state_changed.emit(_current_state)
		
		# Attendre la fin de l'animation
		await _animation_player.animation_finished
		_is_attacking = false
		_update_animation()

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
	# La gravité est gérée par WorldManager.gd
	_handle_movement(delta)
	_handle_jump()
	
	move_and_slide()
	
	# Mettre à jour l'animation selon l'état
	_update_animation()
	
	# Émettre le signal de direction pour l'UI
	move_vector_updated.emit(_input_direction)

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
		var current_speed = run_speed if (_is_running or Input.is_action_pressed("ui_run")) else walk_speed
		
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
#  Gestion du CanvasLayer (pour cacher pendant sélection avatar)
# ─────────────────────────────────────────────
func set_canvas_visible(visible: bool) -> void:
	if _canvas_layer:
		_canvas_layer.visible = visible

func hide_mobile_controls() -> void:
	set_canvas_visible(false)

func show_mobile_controls() -> void:
	set_canvas_visible(true)

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
