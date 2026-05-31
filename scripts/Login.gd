## Login.gd — Ecran d'accueil / authentification
extends Control

signal login_success(user_data: Dictionary)

const SAVE_PATH  := "user://session.cfg"
const CHECK_URL  := "https://www.google.com"
const AUTO_DELAY := 1.8
const API_URL    := "https://TON_ESPACE.hf.space"  # <— remplace par ton URL FastAPI/Render

# ── Noeuds UI ──────────────────────────────────────────────────────────────────
@onready var status_dot      : ColorRect     = $StatusBar/StatusDot
@onready var status_label    : Label         = $StatusBar/StatusLabel
@onready var auto_panel      : VBoxContainer = $MainCard/CardMargin/CardVBox/AutoLoginPanel
@onready var auto_name       : Label         = $MainCard/CardMargin/CardVBox/AutoLoginPanel/AutoLoginName
@onready var auto_class      : Label         = $MainCard/CardMargin/CardVBox/AutoLoginPanel/AutoLoginClass
@onready var auto_spinner    : Label         = $MainCard/CardMargin/CardVBox/AutoLoginPanel/AutoLoginSpinner
@onready var btn_cancel_auto : Button        = $MainCard/CardMargin/CardVBox/AutoLoginPanel/BtnCancelAuto
@onready var manual_panel    : VBoxContainer = $MainCard/CardMargin/CardVBox/ManualLoginPanel
@onready var tab_login       : Button        = $MainCard/CardMargin/CardVBox/ManualLoginPanel/LoginTabRow/TabLogin
@onready var tab_register    : Button        = $MainCard/CardMargin/CardVBox/ManualLoginPanel/LoginTabRow/TabRegister
@onready var login_form      : VBoxContainer = $MainCard/CardMargin/CardVBox/ManualLoginPanel/LoginForm
@onready var register_form   : VBoxContainer = $MainCard/CardMargin/CardVBox/ManualLoginPanel/RegisterForm
@onready var username_edit   : LineEdit = $MainCard/CardMargin/CardVBox/ManualLoginPanel/LoginForm/UsernameEdit
@onready var password_edit   : LineEdit = $MainCard/CardMargin/CardVBox/ManualLoginPanel/LoginForm/PasswordEdit
@onready var remember_check  : CheckBox = $MainCard/CardMargin/CardVBox/ManualLoginPanel/LoginForm/RememberRow/RememberCheck
@onready var btn_login       : Button   = $MainCard/CardMargin/CardVBox/ManualLoginPanel/LoginForm/BtnLogin
@onready var reg_username_edit : LineEdit = $MainCard/CardMargin/CardVBox/ManualLoginPanel/RegisterForm/RegUsernameEdit
@onready var reg_email_edit    : LineEdit = $MainCard/CardMargin/CardVBox/ManualLoginPanel/RegisterForm/RegEmailEdit
@onready var reg_password_edit : LineEdit = $MainCard/CardMargin/CardVBox/ManualLoginPanel/RegisterForm/RegPasswordEdit
@onready var btn_register    : Button   = $MainCard/CardMargin/CardVBox/ManualLoginPanel/RegisterForm/BtnRegister
@onready var error_label     : Label    = $MainCard/CardMargin/CardVBox/ErrorLabel
@onready var offline_notice  : PanelContainer = $OfflineNotice
@onready var btn_offline     : Button   = $BtnPlayOffline

# ── HTTP interne ────────────────────────────────────────────────────────────────
var _http_login    : HTTPRequest
var _http_register : HTTPRequest
var _http_sync     : HTTPRequest   # pour sync stats offline
var _http_check    : HTTPRequest
var _is_online     : bool       = false
var _local_data    : Dictionary = {}
var _auto_timer    : SceneTreeTimer = null

func _ready() -> void:
	# Initialisation des requetes HTTP
	_http_login = HTTPRequest.new()
	add_child(_http_login)
	_http_login.request_completed.connect(_on_login_completed)

	_http_register = HTTPRequest.new()
	add_child(_http_register)
	_http_register.request_completed.connect(_on_register_completed)

	_http_sync = HTTPRequest.new()
	add_child(_http_sync)
	_http_sync.request_completed.connect(_on_sync_completed)

	_connect_signals()
	_local_data = SessionManager.load_local_data()
	_check_connection()

# ─────────────────────────────────────────────
#  Connexion Internet
# ─────────────────────────────────────────────
func _check_connection() -> void:
	_set_status("Verification de la connexion...", Color(0.95, 0.82, 0.35, 0.9))
	_http_check = HTTPRequest.new()
	add_child(_http_check)
	_http_check.timeout = 4.0
	_http_check.request_completed.connect(_on_connection_result)
	if _http_check.request(CHECK_URL) != OK:
		_on_connection_failed()

func _on_connection_result(result: int, _code: int, _headers, _body) -> void:
	_http_check.queue_free()
	if result == HTTPRequest.RESULT_SUCCESS or result == HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED:
		_on_connection_ok()
	else:
		_on_connection_failed()

func _on_connection_ok() -> void:
	_is_online = true
	_set_status("Connecte a Internet", Color(0.35, 0.9, 0.55, 1.0))
	if not _local_data.is_empty() and _local_data.has("username") and not String(_local_data["username"]).is_empty():
		_show_auto_login()
	else:
		_show_manual_login()

func _on_connection_failed() -> void:
	_is_online = false
	_set_status("Hors ligne", Color(0.95, 0.42, 0.32, 1.0))
	offline_notice.visible = true
	if not _local_data.is_empty() and _local_data.has("username") and not String(_local_data["username"]).is_empty():
		btn_offline.visible = true
		_set_status("Hors ligne — Connexion locale disponible", Color(0.95, 0.55, 0.2, 1.0))
	else:
		_show_manual_login()
		btn_login.disabled    = true
		btn_register.disabled = true
		_show_error("Connexion Internet requise pour jouer.")

# ─────────────────────────────────────────────
#  Auto-login
# ─────────────────────────────────────────────
func _show_auto_login() -> void:
	auto_panel.visible   = true
	manual_panel.visible = false
	error_label.text     = ""
	auto_name.text  = String(_local_data.get("username", "Joueur"))
	auto_class.text = String(_local_data.get("class", "Guerrier")) + "  •  Niveau " + str(_local_data.get("level", 1))
	auto_spinner.text = "Connexion automatique dans %d secondes..." % int(AUTO_DELAY)
	_auto_timer = get_tree().create_timer(AUTO_DELAY)
	_auto_timer.timeout.connect(_do_auto_login)

func _do_auto_login() -> void:
	if not is_inside_tree():
		return
	auto_spinner.text = "Connexion en cours..."
	await get_tree().create_timer(0.6).timeout
	if not is_inside_tree():
		return
	_emit_login_success(_local_data)

func _cancel_auto_login() -> void:
	if _auto_timer and _auto_timer.timeout.is_connected(_do_auto_login):
		_auto_timer.timeout.disconnect(_do_auto_login)
	_show_manual_login()

# ─────────────────────────────────────────────
#  Login manuel
# ─────────────────────────────────────────────
func _show_manual_login() -> void:
	auto_panel.visible   = false
	manual_panel.visible = true
	error_label.text     = ""
	_switch_tab(true)

func _switch_tab(is_login: bool) -> void:
	login_form.visible          = is_login
	register_form.visible       = not is_login
	tab_login.button_pressed    = is_login
	tab_register.button_pressed = not is_login
	error_label.text = ""

# ─────────────────────────────────────────────
#  Handler : bouton LOGIN
# ─────────────────────────────────────────────
func _on_login_pressed() -> void:
	var user := username_edit.text.strip_edges()
	var pwd  := password_edit.text.strip_edges()

	if user.is_empty():
		_show_error("Veuillez entrer votre nom d'utilisateur."); return
	if pwd.length() < 4:
		_show_error("Mot de passe trop court."); return
	if not _is_online:
		_show_error("Connexion Internet requise."); return

	btn_login.disabled = true
	btn_login.text     = "Connexion..."
	error_label.text   = ""

	var headers := ["Content-Type: application/json"]
	var body    := JSON.stringify({"name": user, "password": pwd})
	_http_login.request(API_URL + "/get_player_api_key", headers, HTTPClient.METHOD_POST, body)

func _on_login_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	btn_login.disabled = false
	btn_login.text     = "SE CONNECTER"

	if result != HTTPRequest.RESULT_SUCCESS:
		_show_error("Impossible de joindre le serveur."); return

	var json = JSON.parse_string(body.get_string_from_utf8())
	if response_code == 200 and json != null:
		var profile : Dictionary = json.get("profile", {})
		var player  : Dictionary = profile.get("player", {})

		var user_data := {
			"username":      username_edit.text.strip_edges(),
			"class":         "Guerrier",
			"level":         player.get("total_pts", 1) / 10,
			"token":         String(json.get("api_key", "")),
			"p_id":          int(player.get("p_id", -1)),
			"stats":         profile.get("stats", {}),
			"available_pts": int(profile.get("available_pts", 0)),
			"total_pts":     int(player.get("total_pts", 0)),
		}
		if remember_check.button_pressed:
			SessionManager.login(user_data, true)
			SessionManager.save_session(user_data)

		# Sync stats offline si necesaire
		if SessionManager.has_pending_sync():
			_sync_pending_stats(user_data)
		else:
			_emit_login_success(user_data)
	else:
		var err_msg : String = ""
		if json != null:
			err_msg = String(json.get("detail", "Identifiants incorrects."))
		else:
			err_msg = "Erreur serveur."
		_show_error(err_msg)

# ─────────────────────────────────────────────
#  Handler : bouton REGISTER
# ─────────────────────────────────────────────
func _on_register_pressed() -> void:
	var user  := reg_username_edit.text.strip_edges()
	var email := reg_email_edit.text.strip_edges()
	var pwd   := reg_password_edit.text.strip_edges()

	if user.is_empty():
		_show_error("Veuillez choisir un nom d'utilisateur."); return
	if not "@" in email or not "." in email:
		_show_error("Adresse email invalide."); return
	if pwd.length() < 8:
		_show_error("Le mot de passe doit contenir au moins 8 caracteres."); return
	if not _is_online:
		_show_error("Connexion Internet requise pour l'inscription."); return

	btn_register.disabled = true
	btn_register.text     = "Creation du compte..."
	error_label.text      = ""

	var headers := ["Content-Type: application/json"]
	var body    := JSON.stringify({"name": user, "password": pwd})
	_http_register.request(API_URL + "/signup", headers, HTTPClient.METHOD_POST, body)

func _on_register_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	btn_register.disabled = false
	btn_register.text     = "CREER LE COMPTE"

	if result != HTTPRequest.RESULT_SUCCESS:
		_show_error("Impossible de joindre le serveur."); return

	var json = JSON.parse_string(body.get_string_from_utf8())
	if response_code == 201 and json != null:
		var profile : Dictionary = json.get("profile", {})
		var player  : Dictionary = profile.get("player", {})

		var user_data := {
			"username":      reg_username_edit.text.strip_edges(),
			"email":         reg_email_edit.text.strip_edges(),
			"class":         "Guerrier",
			"level":         1,
			"token":         String(json.get("api_key", "")),
			"p_id":          int(player.get("p_id", -1)),
			"stats":         profile.get("stats", {"agility": 10, "strength": 20, "vitality": 15, "shield": 5}),
			"available_pts": int(profile.get("available_pts", 0)),
			"total_pts":     int(player.get("total_pts", 50)),
		}
		SessionManager.login(user_data, true)
		SessionManager.save_session(user_data)
		_emit_login_success(user_data)
	else:
		var err_msg : String = ""
		if json != null:
			err_msg = String(json.get("detail", "Erreur lors de l'inscription."))
		else:
			err_msg = "Erreur serveur."
		_show_error(err_msg)

# ─────────────────────────────────────────────
#  Sync stats offline → online
# ─────────────────────────────────────────────
func _sync_pending_stats(user_data: Dictionary) -> void:
	var pending := SessionManager.consume_pending_stats()
	var pid     := int(user_data.get("p_id", -1))
	var token   := String(user_data.get("token", ""))

	if pid < 0 or token.is_empty() or pending.is_empty():
		_emit_login_success(user_data)
		return

	var headers := [
		"Content-Type: application/json",
		"X-Api-Key: " + token,
	]
	var body := JSON.stringify(pending)
	_http_sync.request(
		API_URL + "/allocate_stats/" + str(pid),
		headers, HTTPClient.METHOD_PATCH, body
	)
	# Passe les user_data en metadata pour y acceder dans le callback
	_http_sync.set_meta("user_data", user_data)

func _on_sync_completed(result: int, _code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS:
		print("[Login] Sync stats offline echoue — stats locales conservees.")
	else:
		print("[Login] Sync stats offline reussie.")
	var user_data : Dictionary = _http_sync.get_meta("user_data", {})
	_emit_login_success(user_data)

# ─────────────────────────────────────────────
#  Mode hors-ligne
# ─────────────────────────────────────────────
func _go_offline() -> void:
	var data := _local_data.duplicate(true)
	data["offline"] = true
	SessionManager.login(data, false)
	_emit_login_success(data)

# ─────────────────────────────────────────────
#  Signaux & navigation
# ─────────────────────────────────────────────
func _connect_signals() -> void:
	tab_login.pressed.connect(func(): _switch_tab(true))
	tab_register.pressed.connect(func(): _switch_tab(false))
	btn_login.pressed.connect(_on_login_pressed)
	btn_register.pressed.connect(_on_register_pressed)
	btn_cancel_auto.pressed.connect(_cancel_auto_login)
	btn_offline.pressed.connect(_go_offline)
	password_edit.text_submitted.connect(func(_t): _on_login_pressed())
	reg_password_edit.text_submitted.connect(func(_t): _on_register_pressed())

func _emit_login_success(data: Dictionary) -> void:
	if not is_inside_tree():
		return
	SessionManager.login(data, _is_online)
	login_success.emit(data)
	# Va vers l'ecran de selection d'avatar et de stats
	get_tree().change_scene_to_file("res://scenes/CharacterScreen.tscn")

# ─────────────────────────────────────────────
#  Helpers UI
# ─────────────────────────────────────────────
func _set_status(text: String, color: Color) -> void:
	status_label.text = text
	status_dot.color  = color

func _show_error(text: String) -> void:
	error_label.text = text
	if login_form.visible:
		btn_login.disabled = false
		btn_login.text     = "SE CONNECTER"
	else:
		btn_register.disabled = false
		btn_register.text     = "CREER LE COMPTE"
