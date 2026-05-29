extends CharacterBody3D
class_name Player

# ─────────────────────────────────────────────
#  Configuration
# ─────────────────────────────────────────────
@export_group("Movement")
@export var walk_speed:    float = 1.0
@export var run_speed:     float = 2.0
@export var acceleration:  float = 10.0
@export var friction:      float = 8.0
@export var jump_velocity: float = 4.5

@export_group("Camera")
@export var camera_sensitivity: float = 0.003
@export var touch_sensitivity:  float = 0.005
@export var min_pitch:          float = -89.0
@export var max_pitch:          float = 89.0

@export_group("Mobile Controls")
@export var enable_mobile_controls: bool = true
@export var joystick_deadzone:      float = 0.1

# ─────────────────────────────────────────────
#  Variables internes
# ─────────────────────────────────────────────
var _is_moving:       bool    = false
var _is_jumping:      bool    = false
var _jump_requested:  bool    = false
var _input_direction: Vector2 = Vector2.ZERO
var _run_held:        bool    = false
var _is_attacking:    bool    = false
var _current_state:   String  = "idle"

# Animation : animation en attente après que la courante se finisse
# → seul jump→idle est immédiat (à l'atterrissage)
# → les autres (walk/run→idle) attendent la fin du cycle courant
var _anim_pending:    String  = ""

# Touch caméra
var _touch_id:        int     = -1
var _touch_start:     Vector2 = Vector2.ZERO
var _last_touch_pos:  Vector2 = Vector2.ZERO
var _is_touching:     bool    = false

# Références
var _camera_orbit:      Node             = null
var _animation_player:  AnimationPlayer  = null
var _canvas_layer:      CanvasLayer      = null
var _game_hud:          GameHUD          = null

# Signaux
signal jump_pressed
signal jump_released
signal move_vector_updated(direction: Vector2)
signal player_died
signal attack_requested(attack_type: String)
signal state_changed(new_state: String)
# Player.gd
@onready var sync: MultiplayerSynchronizer = find_child("MultiplayerSynchronizer", true, false)
@onready var ray_cast: RayCast3D = find_child("RayCast3D", true, false)

func set_world_manager(wm: Node) -> void:
	world_manager = wm
	add_to_group("player")
	add_to_group("characters")
	if wm and wm.has_method("register_character"):
		wm.register_character(self)

func set_network_authority_from_world(peer_id: int) -> void:
	set_multiplayer_authority(peer_id)
	if sync:
		sync.set_multiplayer_authority(peer_id)
# ─────────────────────────────────────────────
#  Initialisation
# ─────────────────────────────────────────────
func _ready() -> void:
	_camera_orbit     = find_child("CameraOrbit", true, false)
	_animation_player = find_child("AnimationPlayer", true, false)

	# Connecter le signal animation_finished pour le système pending
	if _animation_player:
		_animation_player.animation_finished.connect(_on_animation_finished)

	# NOTE: create_mobile_controls() est maintenant appelé directement ici
	# si SessionManager indique qu'il faut le HUD mobile
	if enable_mobile_controls and OS.get_name() in ["Android", "iOS"]:
		_setup_mobile_mode()
	
	# Vérifier si on a besoin du HUD mobile (configuré par MainUI via SessionManager)
	var sm = get_node_or_null("/root/SessionManager")
	if sm and "needs_mobile_hud" in sm and sm.needs_mobile_hud:
		create_mobile_controls()

	find_child("CollisionShape3D2", true, false).add_to_group("player")
	print("[Player] Initialisé — mobile: ", enable_mobile_controls)

# ─────────────────────────────────────────────
#  API publique — appelée par MainUI.gd
# ─────────────────────────────────────────────
## MainUI.gd appelle cette méthode sur le modèle sélectionné
## au moment du clique sur "Lancer la partie".
## Exemple : player_model.create_mobile_controls()
func create_mobile_controls() -> void:
	_create_mobile_controls()

func _create_mobile_controls() -> void:
	_canvas_layer = find_child("CanvasLayer", true, false)
	if not _canvas_layer:
		var canvas_scene := preload("res://scenes/CanvasLayer.tscn") as PackedScene
		if canvas_scene:
			_canvas_layer = canvas_scene.instantiate() as CanvasLayer
			_canvas_layer.name = "CanvasLayer"
			# Configurer le CanvasLayer pour correspondre à la taille de la fenêtre/vueport
			_canvas_layer.layer = 1
			add_child(_canvas_layer)
			_game_hud = _canvas_layer.get_node_or_null("GameHUD") as GameHUD
			if not _game_hud:
				_game_hud = _canvas_layer.find_child("GameHUD", true, false) as GameHUD
			# S'assurer que le GameHUD remplisse tout l'écran
			if _game_hud:
				_game_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
				_game_hud.grow_horizontal = Control.GROW_DIRECTION_BOTH
				_game_hud.grow_vertical = Control.GROW_DIRECTION_BOTH
		else:
			push_error("[Player] Impossible de charger CanvasLayer.tscn")
	else:
		_game_hud = _canvas_layer.get_node_or_null("GameHUD") as GameHUD
		if not _game_hud:
			_game_hud = _canvas_layer.find_child("GameHUD", true, false) as GameHUD

	if _game_hud:
		_game_hud.set_player(self)
		_connect_hud_signals()

func _connect_hud_signals() -> void:
	if not _game_hud:
		return
	var conns := {
		"jump_pressed":  _on_jump_pressed,
		"punch_pressed": _on_punch_pressed,
		"kick_pressed":  _on_kick_pressed,
		"run_pressed":   _on_run_down,
		"run_released":  _on_run_up,
	}
	for sig in conns:
		if _game_hud.has_signal(sig) and not _game_hud.get(sig).is_connected(conns[sig]):
			_game_hud.get(sig).connect(conns[sig])

func _setup_mobile_mode() -> void:
	Engine.max_fps = 60

# ─────────────────────────────────────────────
#  Système d'animations
# ─────────────────────────────────────────────
# Logique (inspirée de Player.cpp / state machine) :
#   • jump  → idle : IMMÉDIAT dès l'atterrissage (is_on_floor)
#   • walk/run → idle : attend la fin du cycle courant (_anim_pending)
#   • punch/kick (attaques) : DOIT se terminer, jamais interrompue
#                              sauf par une nouvelle attaque ou un jump

func _play_animation(anim_name: String) -> void:
	if not _animation_player:
		return
	if not _animation_player.has_animation(anim_name):
		return
	if _current_state == anim_name and _animation_player.is_playing():
		return
	_anim_pending = ""
	_animation_player.play(anim_name)
	_current_state = anim_name
	state_changed.emit(_current_state)

# Callback : déclenché quand l'AnimationPlayer finit une animation
func _on_animation_finished(_anim_name: String) -> void:
	if _anim_pending != "" and not _is_attacking:
		var next := _anim_pending
		_anim_pending = ""
		_play_animation(next)

func _update_animation() -> void:
	if not _animation_player or _is_attacking:
		return

	# Déterminer l'animation souhaitée
	var want: String
	if not is_on_floor():
		want = "jump"
	elif _run_held or _input_direction.length() > joystick_deadzone:
		want = "run" if _run_held else "walk"
	else:
		want = "idle"

	if want == _current_state:
		return

	if want == "idle" and _animation_player.is_playing():
		if _current_state == "jump":
			# Jump → idle : immédiat à l'atterrissage
			_play_animation("idle")
		else:
			# walk/run → idle : on finit le cycle courant d'abord
			_anim_pending = "idle"
	else:
		# Toute autre transition (idle→run, idle→jump, run→jump…) est immédiate
		# Une nouvelle action annule aussi le pending idle
		_anim_pending = ""
		_play_animation(want)

func _perform_attack(attack_type: String) -> void:
	if not _animation_player or not _animation_player.has_animation(attack_type):
		return
	_is_attacking = true
	_anim_pending  = ""
	_animation_player.play(attack_type)
	_current_state = attack_type
	attack_requested.emit(attack_type)
	state_changed.emit(_current_state)
	await _animation_player.animation_finished
	_is_attacking = false
	_update_animation()

# ─────────────────────────────────────────────
#  Handlers boutons HUD mobile
# ─────────────────────────────────────────────
func _on_jump_pressed() -> void:
	_jump_requested = true
	jump_pressed.emit()

func _on_punch_pressed() -> void:
	_perform_attack("punch")

func _on_kick_pressed() -> void:
	_perform_attack("kick")

func _on_run_down() -> void:
	_run_held = true
	if enable_mobile_controls:
		_input_direction = Vector2(0.0, -1.0)

func _on_run_up() -> void:
	_run_held = false
	if enable_mobile_controls:
		_input_direction = Vector2.ZERO

# ─────────────────────────────────────────────
#  Input tactile (rotation caméra mobile)
# ─────────────────────────────────────────────
func _unhandled_input(event: InputEvent) -> void:
	if not enable_mobile_controls:
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_is_touching    = true
			_touch_id       = t.index
			_touch_start    = t.position
			_last_touch_pos = t.position
		elif t.index == _touch_id:
			_is_touching = false
			_touch_id    = -1
	elif event is InputEventScreenDrag:
		if _is_touching and event.index == _touch_id:
			var d     := (event as InputEventScreenDrag)
			var delta := d.relative * touch_sensitivity * 100.0
			rotate_y(-delta.x)
			if _camera_orbit:
				_camera_orbit.rotation_degrees.x = clamp(
					_camera_orbit.rotation_degrees.x - delta.y,
					min_pitch, max_pitch
				)

# ─────────────────────────────────────────────
#  Physics process
# ─────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	_handle_movement(delta)
	_handle_jump()
	move_and_slide()
	_update_animation()
	move_vector_updated.emit(_input_direction)

func _handle_movement(delta: float) -> void:
	if not enable_mobile_controls:
		_input_direction = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")

	# ── Trigonométrie selon la rotation Y du joueur (inspiré de Player.cpp) ──
	# Player.cpp : vel.x -= sin(rotation.y) * speed
	#              vel.z -= cos(rotation.y) * speed
	#
	# Direction forward (local -Z) exprimée en espace monde :
	#   forward_x = -sin(angle_y)   forward_z = -cos(angle_y)
	# Direction right (local +X) exprimée en espace monde :
	#   right_x   =  cos(angle_y)   right_z   = -sin(angle_y)
	var angle: float    = rotation.y
	var forward_x: float = -sin(angle)
	var forward_z: float = -cos(angle)
	var right_x:   float =  cos(angle)
	var right_z:   float = -sin(angle)

	# Combiner les deux axes d'entrée
	var move_x: float = _input_direction.y * forward_x + _input_direction.x * right_x
	var move_z: float = _input_direction.y * forward_z + _input_direction.x * right_z
	var dir := Vector3(move_x, 0.0, move_z)

	if dir.length() > 0.0:
		dir = dir.normalized()
		_is_moving = true
		var speed := run_speed if _run_held else walk_speed
		velocity.x = move_toward(velocity.x, dir.x * speed, acceleration * delta)
		velocity.z = move_toward(velocity.z, dir.z * speed, acceleration * delta)
	else:
		_is_moving = false
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)
		velocity.z = move_toward(velocity.z, 0.0, friction * delta)

func _handle_jump() -> void:
	if is_on_floor():
		_is_jumping = false

	var want_jump := _jump_requested or Input.is_action_just_pressed("ui_accept")
	if want_jump and is_on_floor():
		velocity.y  = jump_velocity
		_is_jumping  = true
	_jump_requested = false

# ─────────────────────────────────────────────
#  API publique
# ─────────────────────────────────────────────
func do_jump() -> void:
	_jump_requested = true

func set_move_input(direction: Vector2) -> void:
	_input_direction = direction

func stop_movement() -> void:
	_input_direction = Vector2.ZERO
	_run_held        = false

func get_is_moving() -> bool:
	return _is_moving

func get_input_direction() -> Vector2:
	return _input_direction

# ─────────────────────────────────────────────
#  CanvasLayer visibilité
# ─────────────────────────────────────────────
func set_canvas_visible(vis: bool) -> void:
	if _canvas_layer:
		_canvas_layer.visible = vis

func hide_mobile_controls() -> void:
	set_canvas_visible(false)

func show_mobile_controls() -> void:
	set_canvas_visible(true)

# ─────────────────────────────────────────────
#  Combat & vie
# ─────────────────────────────────────────────
func take_damage(amount: float, _attacker: Node = null) -> void:
	print("[Player] Dégâts reçus: ", amount)
	if _game_hud:
		_game_hud.take_damage(amount)
	if amount >= 100.0:
		player_died.emit()

func heal(amount: float) -> void:
	print("[Player] Soin: ", amount)
	if _game_hud:
		_game_hud.heal(amount)
