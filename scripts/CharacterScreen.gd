## CharacterScreen.gd
## Ecran de selection d'avatar (P1/P2) et d'allocation de points de statistiques.
## Accede via CharacterScreen.tscn apres le Login.
extends Control

const API_URL := "https://TON_ESPACE.hf.space"  # <— meme URL que Login.gd

# ── Noeuds UI ──────────────────────────────────────────────────────────────────
@onready var avatar_m_btn    : Button  = $AvatarPanel/AvatarMBtn
@onready var avatar_f_btn    : Button  = $AvatarPanel/AvatarFBtn
@onready var username_label  : Label   = $HeaderPanel/UsernameLabel
@onready var pts_available   : Label   = $StatsPanel/PtsAvailable

# Sliders stats (SpinBox ou HSlider selon la scene)
@onready var spin_agility  : SpinBox = $StatsPanel/StatRows/AgilityRow/SpinAgility
@onready var spin_strength : SpinBox = $StatsPanel/StatRows/StrengthRow/SpinStrength
@onready var spin_vitality : SpinBox = $StatsPanel/StatRows/VitalityRow/SpinVitality
@onready var spin_shield   : SpinBox = $StatsPanel/StatRows/ShieldRow/SpinShield

@onready var btn_apply     : Button  = $StatsPanel/BtnApply
@onready var btn_play      : Button  = $FooterPanel/BtnPlay
@onready var status_label  : Label   = $FooterPanel/StatusLabel

# ── Etat interne ───────────────────────────────────────────────────────────────
var _http : HTTPRequest
var _current_model : String = "Model 1"   # "Model 1" = P1 masc, "Model 2" = P2 fem
var _dirty : bool = false                  # stats modifiees non sauvegardees

func _ready() -> void:
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_http_completed)

	_load_session_data()
	_connect_signals()

# ─────────────────────────────────────────────
#  Chargement depuis SessionManager
# ─────────────────────────────────────────────
func _load_session_data() -> void:
	username_label.text = SessionManager.get_username()

	# Avatar par defaut selon la derniere selection
	_current_model = SessionManager.selected_model
	_refresh_avatar_buttons()

	# Remplir les spinbox avec les stats actuelles
	var s := SessionManager.stats
	spin_agility.value  = float(s.get("agility",  0))
	spin_strength.value = float(s.get("strength", 0))
	spin_vitality.value = float(s.get("vitality", 0))
	spin_shield.value   = float(s.get("shield",   0))

	_refresh_pts_label()

# ─────────────────────────────────────────────
#  Connexion signaux
# ─────────────────────────────────────────────
func _connect_signals() -> void:
	avatar_m_btn.pressed.connect(func(): _select_avatar("Model 1"))
	avatar_f_btn.pressed.connect(func(): _select_avatar("Model 2"))
	btn_apply.pressed.connect(_on_apply_pressed)
	btn_play.pressed.connect(_on_play_pressed)

	# Recalcul points disponibles a chaque changement de spinbox
	for spin in [spin_agility, spin_strength, spin_vitality, spin_shield]:
		spin.value_changed.connect(func(_v): _on_stats_changed())

# ─────────────────────────────────────────────
#  Selection avatar
# ─────────────────────────────────────────────
func _select_avatar(model: String) -> void:
	_current_model = model
	SessionManager.selected_model = model
	_refresh_avatar_buttons()

func _refresh_avatar_buttons() -> void:
	var is_m := _current_model == "Model 1"
	avatar_m_btn.button_pressed = is_m
	avatar_f_btn.button_pressed = not is_m

# ─────────────────────────────────────────────
#  Stats
# ─────────────────────────────────────────────
func _on_stats_changed() -> void:
	_dirty = true
	_refresh_pts_label()
	btn_apply.disabled = (_get_pts_used() > SessionManager.total_pts)

func _get_pts_used() -> int:
	return (int(spin_agility.value) + int(spin_strength.value)
		+ int(spin_vitality.value) + int(spin_shield.value))

func _refresh_pts_label() -> void:
	var used  : int = _get_pts_used()
	var avail : int = maxi(SessionManager.total_pts - used, 0)
	pts_available.text = "Points disponibles : %d" % avail
	# Colore en rouge si depassement
	pts_available.add_theme_color_override(
		"font_color",
		Color.RED if used > SessionManager.total_pts else Color.WHITE
	)

func _build_stats_dict() -> Dictionary:
	return {
		"agility":  int(spin_agility.value),
		"strength": int(spin_strength.value),
		"vitality": int(spin_vitality.value),
		"shield":   int(spin_shield.value),
	}

# ─────────────────────────────────────────────
#  Bouton "Changer" (PATCH /allocate_stats)
# ─────────────────────────────────────────────
func _on_apply_pressed() -> void:
	var used := _get_pts_used()
	if used > SessionManager.total_pts:
		_set_status("Points insuffisants !", Color.RED); return

	var new_stats := _build_stats_dict()

	if not SessionManager.is_online:
		# Mode offline : sauvegarder localement, envoyer au prochain login
		SessionManager.queue_stats_for_sync(new_stats)
		_set_status("Stats sauvegardees localement (sync au prochain login).", Color.YELLOW)
		_dirty = false
		return

	var pid   := SessionManager.p_id
	var token := SessionManager.get_token()

	if pid < 0 or token.is_empty():
		_set_status("Session invalide, reconnectez-vous.", Color.RED); return

	btn_apply.disabled = true
	btn_apply.text     = "Enregistrement..."
	status_label.text  = ""

	var headers := [
		"Content-Type: application/json",
		"X-Api-Key: " + token,
	]
	var body := JSON.stringify(new_stats)
	_http.request(API_URL + "/allocate_stats/" + str(pid), headers, HTTPClient.METHOD_PATCH, body)

func _on_http_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	btn_apply.disabled = false
	btn_apply.text     = "Changer"

	if result != HTTPRequest.RESULT_SUCCESS:
		_set_status("Erreur reseau.", Color.RED); return

	var json = JSON.parse_string(body.get_string_from_utf8())
	if response_code == 200 and json != null:
		var profile : Dictionary = json.get("profile", {})
		var new_stats : Dictionary = profile.get("stats", _build_stats_dict())
		var avail     : int        = int(profile.get("available_pts", 0))

		# Mettre a jour le SessionManager
		SessionManager.stats         = new_stats
		SessionManager.available_pts = avail

		# Rafraichir l'affichage
		_dirty = false
		_refresh_pts_label()
		_set_status("Stats enregistrees !", Color.GREEN)
	else:
		var msg := "Erreur."
		if json != null:
			msg = String(json.get("detail", "Erreur."))
		_set_status(msg, Color.RED)

# ─────────────────────────────────────────────
#  Bouton "Jouer"
# ─────────────────────────────────────────────
func _on_play_pressed() -> void:
	if _dirty:
		# Stats non sauvegardees : on applique localement sans attendre
		SessionManager.apply_stats_locally(_build_stats_dict())

	SessionManager.selected_model = _current_model
	get_tree().change_scene_to_file("res://scenes/MainUI.tscn")

# ─────────────────────────────────────────────
#  Helper UI
# ─────────────────────────────────────────────
func _set_status(text: String, color: Color) -> void:
	status_label.text = text
	status_label.add_theme_color_override("font_color", color)
