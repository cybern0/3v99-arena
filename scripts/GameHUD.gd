extends Control
class_name GameHUD

# ─────────────────────────────────────────────
#  Configuration
# ─────────────────────────────────────────────
@export var show_on_mobile_only: bool = true
@export var block_hold_mode:     bool = true   # true = bloquer tant que tenu, false = toggle

# ─────────────────────────────────────────────
#  Noeuds UI (chemins relatifs à GameHUD)
# ─────────────────────────────────────────────

# ── Barres de statut ──────────────────────────
@onready var health_bar      : ProgressBar    = get_node_or_null("TopBar/TopBarInner/HPSection/HealthBar")
@onready var health_label    : Label          = get_node_or_null("TopBar/TopBarInner/HPSection/HealthBar/HealthLabel")
@onready var stamina_bar     : ProgressBar    = get_node_or_null("TopBar/TopBarInner/StamSection/StaminaBar")
@onready var energy_bar      : ProgressBar    = get_node_or_null("TopBar/TopBarInner/EnerSection/EnergyBar")
@onready var xp_bar          : ProgressBar    = get_node_or_null("TopBar/TopBarInner/XPSection/XPBar")
@onready var level_label     : Label          = get_node_or_null("TopBar/TopBarInner/XPSection/XPBar/LevelLabel")
@onready var score_label     : Label          = get_node_or_null("TopBar/TopBarInner/ScoreLabel")
@onready var timer_label     : Label          = get_node_or_null("TopBar/TopBarInner/TimerLabel")
@onready var pause_button    : Button         = get_node_or_null("TopBar/TopBarInner/PauseButton")

# ── Barre Boss ────────────────────────────────
@onready var boss_bar        : PanelContainer = get_node_or_null("BossBar")
@onready var boss_hp_bar     : ProgressBar    = get_node_or_null("BossBar/BossBarInner/BossHPBar")
@onready var boss_hp_label   : Label          = get_node_or_null("BossBar/BossBarInner/BossHPBar/BossHPLabel")
@onready var boss_name_label : Label          = get_node_or_null("BossBar/BossBarInner/BossNameLabel")

# ── Block Feedback ────────────────────────────
@onready var block_feedback  : Control        = get_node_or_null("BlockFeedback")

# ── AnimationPlayer dédié au block ───────────
## Ajouter l'animation "block" dans l'éditeur Godot sur ce node.
## Elle anime BlockFeedback (visible, modulate, BlockIcon.scale, etc.)
@onready var animation_player_block : AnimationPlayer = get_node_or_null("AnimationPlayerBlock")

# ── Settings & Minimap ────────────────────────
@onready var settings_panel  : Control        = get_node_or_null("SettingsPanel")
@onready var minimap_container: Control       = get_node_or_null("MinimapContainer")
@onready var minimap_viewport : SubViewport   = get_node_or_null("MinimapContainer/MinimapViewport")

# ── Boutons mobiles ───────────────────────────
@onready var mobile_controls : Control = get_node_or_null("MobileControls")
@onready var jump_button     : Button  = get_node_or_null("MobileControls/JumpButton")
@onready var punch_button    : Button  = get_node_or_null("MobileControls/PunchButton")
@onready var kick_button     : Button  = get_node_or_null("MobileControls/KickButton")
@onready var block_button    : Button  = get_node_or_null("MobileControls/BlockButton")
@onready var run_button      : Button  = get_node_or_null("MobileControls/RunButton")

# ─────────────────────────────────────────────
#  Etat
# ─────────────────────────────────────────────
var current_health  : float = 100.0
var max_health      : float = 100.0
var current_stamina : float = 100.0
var max_stamina     : float = 100.0
var current_energy  : float = 100.0
var max_energy      : float = 100.0
var current_xp      : float = 0.0
var xp_to_level     : float = 100.0
var current_level   : int   = 1
var current_score   : int   = 0
var game_time       : float = 0.0
var is_game_paused  : bool  = false
var is_blocking     : bool  = false

var _player       : Node   = null
var _current_anim : String = ""

const ANIM_DURATIONS := {
	"punch": 0.8,
	"kick":  0.8,
	"jump":  1.0,
	"react": 0.6,
	"die":   1.5,
	"block": 0.0,    # 0 = durée contrôlée par AnimationPlayerBlock
}

# ─────────────────────────────────────────────
#  Signaux
# ─────────────────────────────────────────────
signal health_changed(new_value: float)
signal stamina_changed(new_value: float)
signal energy_changed(new_value: float)
signal xp_changed(new_value: float)
signal level_up(new_level: int)
signal game_paused(is_paused: bool)
signal settings_toggled(is_visible: bool)
signal jump_pressed
signal punch_pressed
signal kick_pressed
signal block_pressed
signal block_released
signal run_pressed
signal run_released

# ─────────────────────────────────────────────
#  Initialisation
# ─────────────────────────────────────────────
func _ready() -> void:
	_connect_signals()
	_update_ui()
	await get_tree().process_frame
	_find_player()
	print("[GameHUD] Initialisé — player : ", _player.name if _player else "introuvable")

# ─────────────────────────────────────────────
#  Connexion des signaux
# ─────────────────────────────────────────────
func _connect_signals() -> void:
	if pause_button:
		pause_button.pressed.connect(_toggle_pause)
	if settings_panel:
		settings_panel.visible = false

	# ── Boutons mobiles ──────────────────────
	if jump_button:
		jump_button.pressed.connect(_on_jump_pressed)
	if punch_button:
		punch_button.pressed.connect(_on_punch_pressed)
	if kick_button:
		kick_button.pressed.connect(_on_kick_pressed)
	if run_button:
		run_button.button_down.connect(_on_run_down)
		run_button.button_up.connect(_on_run_up)

	# ── Block : button_down / button_up pour maintien ──────────────────────
	if block_button:
		if block_hold_mode:
			block_button.button_down.connect(_on_block_pressed)
			block_button.button_up.connect(_on_block_released)
		else:
			block_button.pressed.connect(_on_block_toggle)

# ─────────────────────────────────────────────
#  Recherche du Player
# ─────────────────────────────────────────────
func _find_player() -> void:
	if not is_inside_tree():
		await ready
		_find_player()
		return
	var groupe := get_tree().get_nodes_in_group("player")
	if groupe.size() > 0:
		_player = groupe[0]
		return
	var scene_root := get_tree().current_scene
	if scene_root:
		_player = scene_root.find_child("Player", true, false)

func set_player(player: Node) -> void:
	_player = player

# ─────────────────────────────────────────────
#  AnimationPlayer character
# ─────────────────────────────────────────────
func _get_anim_player() -> AnimationPlayer:
	if not _player:
		return null
	var ap := _player.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if ap == null:
		ap = _player.find_child("AnimationPlayer", true, false) as AnimationPlayer
	return ap

func _play_anim(anim_name: String, one_shot: bool = false) -> void:
	var ap := _get_anim_player()
	if ap == null:
		return
	if not ap.has_animation(anim_name):
		push_warning("[GameHUD] Anim '%s' introuvable." % anim_name)
		return
	if _current_anim == anim_name and ap.is_playing():
		return
	_current_anim = anim_name
	ap.play(anim_name)
	if one_shot and ANIM_DURATIONS.has(anim_name) and ANIM_DURATIONS[anim_name] > 0.0:
		await get_tree().create_timer(ANIM_DURATIONS[anim_name]).timeout
		_play_anim("idle")

# ─────────────────────────────────────────────
#  AnimationPlayerBlock — animation "block"
# ─────────────────────────────────────────────

## Déclenche l'animation "block" via AnimationPlayerBlock.
## Appelé automatiquement par _on_block_pressed() et manuellement si besoin.
func play_block_animation(playing: bool = true) -> void:
	if not animation_player_block:
		# Fallback : toggle visibilité du feedback directement
		if block_feedback:
			block_feedback.visible = playing
		return

	if playing:
		if animation_player_block.has_animation("block"):
			animation_player_block.play("block")
		elif block_feedback:
			block_feedback.visible = true
	else:
		animation_player_block.stop()
		if block_feedback:
			block_feedback.visible = false

# ─────────────────────────────────────────────
#  Handlers boutons mobiles
# ─────────────────────────────────────────────
func _on_jump_pressed() -> void:
	jump_pressed.emit()
	_play_anim("jump", true)

func _on_punch_pressed() -> void:
	punch_pressed.emit()
	_play_anim("punch", true)

func _on_kick_pressed() -> void:
	kick_pressed.emit()
	_play_anim("kick", true)

func _on_run_down() -> void:
	run_pressed.emit()
	_play_anim("run")

func _on_run_up() -> void:
	run_released.emit()
	_play_anim("idle")

# ── Block (mode maintien) ────────────────────
func _on_block_pressed() -> void:
	if is_blocking:
		return
	is_blocking = true
	block_pressed.emit()
	_play_anim("block")
	play_block_animation(true)
	consume_stamina(5.0)

func _on_block_released() -> void:
	if not is_blocking:
		return
	is_blocking = false
	block_released.emit()
	play_block_animation(false)
	_play_anim("idle")

# ── Block (mode toggle) ──────────────────────
func _on_block_toggle() -> void:
	if is_blocking:
		_on_block_released()
	else:
		_on_block_pressed()

func _on_pause_pressed() -> void:
	_toggle_pause()

# ─────────────────────────────────────────────
#  Mise à jour UI
# ─────────────────────────────────────────────
func _update_ui() -> void:
	_update_health_bar()
	_update_stamina_bar()
	_update_energy_bar()
	_update_xp_bar()
	_update_score()
	_update_timer()

func _update_health_bar() -> void:
	if health_bar:
		health_bar.max_value = max_health
		health_bar.value = current_health
	if health_label:
		health_label.text = "%d / %d" % [int(current_health), int(max_health)]

func _update_stamina_bar() -> void:
	if stamina_bar:
		stamina_bar.max_value = max_stamina
		stamina_bar.value = current_stamina

func _update_energy_bar() -> void:
	if energy_bar:
		energy_bar.max_value = max_energy
		energy_bar.value = current_energy

func _update_xp_bar() -> void:
	if xp_bar:
		xp_bar.max_value = xp_to_level
		xp_bar.value = current_xp
	if level_label:
		level_label.text = "Niv. %d" % current_level

func _update_score() -> void:
	if score_label:
		score_label.text = "⭐ %d" % current_score

func _update_timer() -> void:
	if timer_label:
		var minutes := int(game_time) / 60
		var seconds  := int(game_time) % 60
		timer_label.text = "%02d:%02d" % [minutes, seconds]

# ─────────────────────────────────────────────
#  Gestion Santé
# ─────────────────────────────────────────────
func set_health(value: float, max_value: float = 100.0) -> void:
	max_health     = max_value
	current_health = clamp(value, 0.0, max_health)
	_update_health_bar()
	health_changed.emit(current_health)
	if current_health <= 0.0:
		_on_player_death()

func heal(amount: float)       -> void: set_health(current_health + amount, max_health)
func take_damage(amount: float) -> void:
	# Le block réduit les dégâts de 70%
	var dmg := amount * (0.30 if is_blocking else 1.0)
	set_health(current_health - dmg, max_health)
	_play_anim("react", true)

func _on_player_death() -> void:
	_play_anim("die", false)
	print("[GameHUD] Player Death")

# ─────────────────────────────────────────────
#  Gestion Stamina
# ─────────────────────────────────────────────
func set_stamina(value: float, max_value: float = 100.0) -> void:
	max_stamina     = max_value
	current_stamina = clamp(value, 0.0, max_stamina)
	_update_stamina_bar()
	stamina_changed.emit(current_stamina)

func consume_stamina(amount: float)    -> void: set_stamina(current_stamina - amount, max_stamina)
func regenerate_stamina(amount: float) -> void: set_stamina(current_stamina + amount, max_stamina)

# ─────────────────────────────────────────────
#  Gestion Énergie (feature ML : energy_ratio)
# ─────────────────────────────────────────────
func set_energy(value: float, max_value: float = 100.0) -> void:
	max_energy     = max_value
	current_energy = clamp(value, 0.0, max_energy)
	_update_energy_bar()
	energy_changed.emit(current_energy)

func get_energy_ratio() -> float:
	return current_energy / max_energy if max_energy > 0.0 else 0.0

# ─────────────────────────────────────────────
#  Barre de vie du Boss
# ─────────────────────────────────────────────
func show_boss_bar(boss_name: String = "Boss") -> void:
	if boss_bar:
		boss_bar.visible = true
	if boss_name_label:
		boss_name_label.text = "☠ " + boss_name

func hide_boss_bar() -> void:
	if boss_bar:
		boss_bar.visible = false

func set_boss_hp(ratio: float, boss_name: String = "") -> void:
	if not boss_bar or not boss_bar.visible:
		show_boss_bar(boss_name if not boss_name.is_empty() else "Boss")
	if boss_hp_bar:
		boss_hp_bar.value = clamp(ratio * 100.0, 0.0, 100.0)
	if boss_hp_label:
		boss_hp_label.text = "%d%%" % int(ratio * 100.0)
	if not boss_name.is_empty() and boss_name_label:
		boss_name_label.text = "☠ " + boss_name

# ─────────────────────────────────────────────
#  Gestion XP & Level
# ─────────────────────────────────────────────
func add_xp(amount: float) -> void:
	current_xp += amount
	while current_xp >= xp_to_level:
		current_xp    -= xp_to_level
		current_level  += 1
		xp_to_level    *= 1.2
		level_up.emit(current_level)
	_update_xp_bar()

func set_level(level: int) -> void:
	current_level = level
	_update_xp_bar()

# ─────────────────────────────────────────────
#  Score & Timer
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
	is_game_paused = not is_game_paused
	get_tree().paused = is_game_paused
	game_paused.emit(is_game_paused)
	if pause_button:
		pause_button.text = "▶" if is_game_paused else "⏸"

func toggle_settings() -> void:
	if settings_panel:
		settings_panel.visible = not settings_panel.visible
		settings_toggled.emit(settings_panel.visible)

func show_settings(show: bool) -> void:
	if settings_panel:
		settings_panel.visible = show

# ─────────────────────────────────────────────
#  Minimap
# ─────────────────────────────────────────────
func setup_minimap(camera: Camera3D) -> void:
	if minimap_viewport and camera:
		var minimap_camera := minimap_viewport.get_camera_3d()
		if minimap_camera:
			minimap_camera.current = true
			minimap_camera.position = camera.position + Vector3(0, 20, 0)
			minimap_camera.look_at(camera.position)

func update_minimap_position(player_pos: Vector3) -> void:
	if minimap_viewport:
		var minimap_camera := minimap_viewport.get_camera_3d()
		if minimap_camera:
			minimap_camera.position = player_pos + Vector3(0, 20, 0)
			minimap_camera.look_at(player_pos)

# ─────────────────────────────────────────────
#  Process
# ─────────────────────────────────────────────
func _process(delta: float) -> void:
	update_timer(delta)
	# Régénération stamina (réduite si on bloque)
	if current_stamina < max_stamina:
		var regen_rate := 2.5 if is_blocking else 5.0
		regenerate_stamina(delta * regen_rate)
	# Consommation énergie si blocage maintenu
	if is_blocking and block_hold_mode:
		set_energy(current_energy - delta * 8.0)
		if current_energy <= 0.0:
			_on_block_released()   # Block cassé par manque d'énergie

# ─────────────────────────────────────────────
#  Utilitaires
# ─────────────────────────────────────────────
func show_hud(show: bool) -> void: visible = show

func fade_out(duration: float = 1.0) -> void:
	var tween := create_tween()
	tween.tween_property(self, "self_modulate:a", 0.0, duration)
	tween.tween_callback(func(): visible = false)

func fade_in(duration: float = 1.0) -> void:
	visible = true
	var tween := create_tween()
	tween.tween_property(self, "self_modulate:a", 1.0, duration)
