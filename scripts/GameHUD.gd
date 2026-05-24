extends CanvasLayer
class_name GameHUD

# ─────────────────────────────────────────────
#  Configuration
# ─────────────────────────────────────────────
@export var show_on_mobile_only: bool = true

# ─────────────────────────────────────────────
#  Noeuds UI
# ─────────────────────────────────────────────
@onready var health_bar: ProgressBar = $HealthBar
@onready var health_label: Label = $HealthBar/HealthLabel
@onready var stamina_bar: ProgressBar = $StaminaBar
@onready var xp_bar: ProgressBar = $XPBar
@onready var level_label: Label = $LevelLabel
@onready var minimap_container: Control = $MinimapContainer
@onready var minimap_viewport: SubViewport = $MinimapContainer/MinimapViewport
@onready var score_label: Label = $ScoreLabel
@onready var timer_label: Label = $TimerLabel
@onready var pause_button: Button = $PauseButton
@onready var settings_panel: Control = $SettingsPanel

# ─────────────────────────────────────────────
#  État
# ─────────────────────────────────────────────
var current_health: float = 100.0
var max_health: float = 100.0
var current_stamina: float = 100.0
var max_stamina: float = 100.0
var current_xp: float = 0.0
var xp_to_level: float = 100.0
var current_level: int = 1
var current_score: int = 0
var game_time: float = 0.0
var is_game_paused: bool = false

# Signaux
signal health_changed(new_value: float)
signal stamina_changed(new_value: float)
signal xp_changed(new_value: float)
signal level_up(new_level: int)
signal game_paused(is_paused: bool)
signal settings_toggled(is_visible: bool)

# ─────────────────────────────────────────────
#  Initialisation
# ─────────────────────────────────────────────
func _ready() -> void:
	# Masquer si non mobile et option activée
	if show_on_mobile_only and OS.get_name() not in ["Android", "iOS"]:
		# Garder visible pour debug sur desktop
		pass
	
	_connect_signals()
	_update_ui()
	
	print("[GameHUD] Initialisé")

func _connect_signals() -> void:
	if pause_button:
		pause_button.pressed.connect(_toggle_pause)
	
	if settings_panel:
		settings_panel.visible = false

# ─────────────────────────────────────────────
#  Mise à jour UI
# ─────────────────────────────────────────────
func _update_ui() -> void:
	_update_health_bar()
	_update_stamina_bar()
	_update_xp_bar()
	_update_score()
	_update_timer()

func _update_health_bar() -> void:
	if health_bar:
		health_bar.max_value = max_health
		health_bar.value = current_health
	if health_label:
		health_label.text = f"{int(current_health)} / {int(max_health)}"

func _update_stamina_bar() -> void:
	if stamina_bar:
		stamina_bar.max_value = max_stamina
		stamina_bar.value = current_stamina

func _update_xp_bar() -> void:
	if xp_bar:
		xp_bar.max_value = xp_to_level
		xp_bar.value = current_xp
	if level_label:
		level_label.text = f"Niv. {current_level}"

func _update_score() -> void:
	if score_label:
		score_label.text = f"Score: {current_score}"

func _update_timer() -> void:
	if timer_label:
		var minutes = int(game_time) / 60
		var seconds = int(game_time) % 60
		timer_label.text = f"{minutes:02d}:{seconds:02d}"

# ─────────────────────────────────────────────
#  Gestion Santé
# ─────────────────────────────────────────────
func set_health(value: float, max_value: float = 100.0) -> void:
	max_health = max_value
	current_health = clamp(value, 0, max_health)
	_update_health_bar()
	health_changed.emit(current_health)
	
	if current_health <= 0:
		_on_player_death()

func heal(amount: float) -> void:
	set_health(current_health + amount, max_health)

func take_damage(amount: float) -> void:
	set_health(current_health - amount, max_health)

func _on_player_death() -> void:
	print("[GameHUD] Player Death")
	# À connecter au GameOver

# ─────────────────────────────────────────────
#  Gestion Stamina
# ─────────────────────────────────────────────
func set_stamina(value: float, max_value: float = 100.0) -> void:
	max_stamina = max_value
	current_stamina = clamp(value, 0, max_stamina)
	_update_stamina_bar()
	stamina_changed.emit(current_stamina)

func consume_stamina(amount: float) -> void:
	set_stamina(current_stamina - amount, max_stamina)

func regenerate_stamina(amount: float) -> void:
	set_stamina(current_stamina + amount, max_stamina)

# ─────────────────────────────────────────────
#  Gestion XP & Level
# ─────────────────────────────────────────────
func add_xp(amount: float) -> void:
	current_xp += amount
	while current_xp >= xp_to_level:
		current_xp -= xp_to_level
		current_level += 1
		xp_to_level *= 1.2  # Augmentation progressive
		level_up.emit(current_level)
	_update_xp_bar()

func set_level(level: int) -> void:
	current_level = level
	_update_xp_bar()

# ─────────────────────────────────────────────
#  Gestion Score & Timer
# ─────────────────────────────────────────────
func add_score(points: int) -> void:
	current_score += points
	_update_score()

func update_timer(delta: float) -> void:
	if not is_game_paused:
		game_time += delta
		_update_timer()

# ─────────────────────────────────────────────
#  Pause & Settings
# ─────────────────────────────────────────────
func _toggle_pause() -> void:
	is_game_paused = !is_game_paused
	get_tree().paused = is_game_paused
	game_paused.emit(is_game_paused)
	
	if pause_button:
		pause_button.text = "▶" if is_game_paused else "⏸"

func toggle_settings() -> void:
	if settings_panel:
		settings_panel.visible = !settings_panel.visible
		settings_toggled.emit(settings_panel.visible)

func show_settings(show: bool) -> void:
	if settings_panel:
		settings_panel.visible = show

# ─────────────────────────────────────────────
#  Minimap
# ─────────────────────────────────────────────
func setup_minimap(camera: Camera3D) -> void:
	if minimap_viewport and camera:
		# Configurer la caméra de la minimap
		var minimap_camera = minimap_viewport.get_camera_3d()
		if minimap_camera:
			minimap_camera.current = true
			# Positionner en vue de dessus
			minimap_camera.position = camera.position + Vector3(0, 20, 0)
			minimap_camera.look_at(camera.position)

func update_minimap_position(player_pos: Vector3) -> void:
	if minimap_viewport:
		var minimap_camera = minimap_viewport.get_camera_3d()
		if minimap_camera:
			minimap_camera.position = player_pos + Vector3(0, 20, 0)
			minimap_camera.look_at(player_pos)

# ─────────────────────────────────────────────
#  Process
# ─────────────────────────────────────────────
func _process(delta: float) -> void:
	update_timer(delta)
	
	# Régénération passive de stamina
	if current_stamina < max_stamina:
		regenerate_stamina(delta * 5.0)  # 5 par seconde

# ─────────────────────────────────────────────
#  Utilitaires
# ─────────────────────────────────────────────
func show_hud(show: bool) -> void:
	visible = show

func fade_out(duration: float = 1.0) -> void:
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, duration)
	tween.tween_callback(func(): visible = false)

func fade_in(duration: float = 1.0) -> void:
	visible = true
	modulate.a = 0.0
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, duration)
