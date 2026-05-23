extends Control

# ─────────────────────────────────────────────
#  Signaux
# ─────────────────────────────────────────────
signal login_success(user_data: Dictionary)

# ─────────────────────────────────────────────
#  Constantes
# ─────────────────────────────────────────────
const SAVE_PATH      := "user://session.cfg"
const CHECK_URL      := "https://www.google.com"   # URL ping connexion
const AUTO_DELAY     := 1.8                         # secondes avant auto-login

# ─────────────────────────────────────────────
#  Noeuds
# ─────────────────────────────────────────────
@onready var status_dot        : ColorRect = $StatusBar/StatusDot
@onready var status_label      : Label     = $StatusBar/StatusLabel

@onready var auto_panel        : VBoxContainer = $MainCard/CardVBox/AutoLoginPanel
@onready var auto_name         : Label         = $MainCard/CardVBox/AutoLoginPanel/AutoLoginName
@onready var auto_class        : Label         = $MainCard/CardVBox/AutoLoginPanel/AutoLoginClass
@onready var auto_spinner      : Label         = $MainCard/CardVBox/AutoLoginPanel/AutoLoginSpinner
@onready var btn_cancel_auto   : Button        = $MainCard/CardVBox/AutoLoginPanel/BtnCancelAuto

@onready var manual_panel      : VBoxContainer = $MainCard/CardVBox/ManualLoginPanel
@onready var tab_login         : Button        = $MainCard/CardVBox/ManualLoginPanel/LoginTabRow/TabLogin
@onready var tab_register      : Button        = $MainCard/CardVBox/ManualLoginPanel/LoginTabRow/TabRegister
@onready var login_form        : VBoxContainer = $MainCard/CardVBox/ManualLoginPanel/LoginForm
@onready var register_form     : VBoxContainer = $MainCard/CardVBox/ManualLoginPanel/RegisterForm

@onready var username_edit     : LineEdit = $MainCard/CardVBox/ManualLoginPanel/LoginForm/UsernameEdit
@onready var password_edit     : LineEdit = $MainCard/CardVBox/ManualLoginPanel/LoginForm/PasswordEdit
@onready var remember_check    : CheckBox = $MainCard/CardVBox/ManualLoginPanel/LoginForm/RememberRow/RememberCheck
@onready var btn_login         : Button   = $MainCard/CardVBox/ManualLoginPanel/LoginForm/BtnLogin

@onready var reg_username_edit : LineEdit = $MainCard/CardVBox/ManualLoginPanel/RegisterForm/RegUsernameEdit
@onready var reg_email_edit    : LineEdit = $MainCard/CardVBox/ManualLoginPanel/RegisterForm/RegEmailEdit
@onready var reg_password_edit : LineEdit = $MainCard/CardVBox/ManualLoginPanel/RegisterForm/RegPasswordEdit
@onready var btn_register      : Button   = $MainCard/CardVBox/ManualLoginPanel/RegisterForm/BtnRegister

@onready var error_label       : Label    = $MainCard/CardVBox/ErrorLabel
@onready var offline_notice    : VBoxContainer = $OfflineNotice
@onready var btn_offline       : Button   = $BtnPlayOffline

# ─────────────────────────────────────────────
#  Etat interne
# ─────────────────────────────────────────────
var _http_check  : HTTPRequest
var _is_online   : bool = false
var _local_data  : Dictionary = {}
var _auto_timer  : SceneTreeTimer = null

# ─────────────────────────────────────────────
#  Cycle de vie
# ─────────────────────────────────────────────
func _ready() -> void:
	_connect_signals()
	_load_local_data()
	_check_connection()

func _connect_signals() -> void:
	tab_login.pressed.connect(func(): _switch_tab(true))
	tab_register.pressed.connect(func(): _switch_tab(false))
	btn_login.pressed.connect(_on_login_pressed)
	btn_register.pressed.connect(_on_register_pressed)
	btn_cancel_auto.pressed.connect(_cancel_auto_login)
	btn_offline.pressed.connect(_go_offline)
	password_edit.text_submitted.connect(func(_t): _on_login_pressed())
	reg_password_edit.text_submitted.connect(func(_t): _on_register_pressed())

# ─────────────────────────────────────────────
#  1. Verifier la connexion Internet
# ─────────────────────────────────────────────
func _check_connection() -> void:
	_set_status("Verification de la connexion...", Color(0.95, 0.82, 0.35, 0.9))

	_http_check = HTTPRequest.new()
	add_child(_http_check)
	_http_check.timeout = 4.0
	_http_check.request_completed.connect(_on_connection_result)

	var err = _http_check.request(CHECK_URL)
	if err != OK:
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

	# Donnees locales presentes → auto-login
	if not _local_data.is_empty() and _local_data.has("username"):
		_show_auto_login()
	else:
		_show_manual_login()

func _on_connection_failed() -> void:
	_is_online = false
	_set_status("Hors ligne", Color(0.95, 0.42, 0.32, 1.0))
	offline_notice.visible = true

	# Donnees locales → proposer hors-ligne
	if not _local_data.is_empty() and _local_data.has("username"):
		btn_offline.visible = true
		_set_status("Hors ligne — Connexion locale disponible", Color(0.95, 0.55, 0.2, 1.0))
	else:
		# Aucune donnee locale, aucune connexion → formulaire desactive
		_show_manual_login()
		btn_login.disabled = true
		btn_register.disabled = true
		_show_error("Connexion Internet requise pour jouer.")

# ─────────────────────────────────────────────
#  2. Auto-login
# ─────────────────────────────────────────────
func _show_auto_login() -> void:
	auto_panel.visible  = true
	manual_panel.visible = false
	error_label.text    = ""

	auto_name.text  = _local_data.get("username", "Joueur")
	auto_class.text = _local_data.get("class", "Guerrier")  + "  •  Niveau " + str(_local_data.get("level", 1))

	auto_spinner.text = "Connexion automatique dans %d secondes..." % int(AUTO_DELAY)

	_auto_timer = get_tree().create_timer(AUTO_DELAY)
	_auto_timer.timeout.connect(_do_auto_login)

func _do_auto_login() -> void:
	auto_spinner.text = "Connexion en cours..."
	# Simuler appel serveur ici (HTTP POST avec token sauvegarde)
	# _http_auth.request(SERVER_URL + "/auth/token", ...)
	await get_tree().create_timer(0.6).timeout
	_emit_login_success(_local_data)

func _cancel_auto_login() -> void:
	if _auto_timer:
		# Invalider le timer en desconnectant son signal
		if _auto_timer.timeout.is_connected(_do_auto_login):
			_auto_timer.timeout.disconnect(_do_auto_login)
	_show_manual_login()

# ─────────────────────────────────────────────
#  3. Login manuel
# ─────────────────────────────────────────────
func _show_manual_login() -> void:
	auto_panel.visible   = false
	manual_panel.visible = true
	error_label.text     = ""
	_switch_tab(true)

func _switch_tab(is_login: bool) -> void:
	login_form.visible    = is_login
	register_form.visible = not is_login
	tab_login.button_pressed    = is_login
	tab_register.button_pressed = not is_login
	error_label.text = ""

func _on_login_pressed() -> void:
	var user = username_edit.text.strip_edges()
	var pwd  = password_edit.text.strip_edges()

	if user.is_empty():
		_show_error("Veuillez entrer votre nom d'utilisateur.")
		return
	if pwd.length() < 4:
		_show_error("Mot de passe trop court.")
		return
	if not _is_online:
		_show_error("Connexion Internet requise.")
		return

	btn_login.disabled = true
	btn_login.text = "Connexion..."
	_show_error("")

	# Simuler appel serveur
	# var http = HTTPRequest.new(); add_child(http)
	# http.request(SERVER_URL + "/auth/login", [...], HTTPClient.METHOD_POST, body)
	await get_tree().create_timer(1.0).timeout

	# Succes (remplacer par la reponse reelle du serveur)
	var user_data := {
		"username": user,
		"class":    "Guerrier",
		"level":    1,
		"token":    "tok_" + user.md5_text().left(16),
	}
	if remember_check.button_pressed:
		_save_local_data(user_data)

	_emit_login_success(user_data)

func _on_register_pressed() -> void:
	var user  = reg_username_edit.text.strip_edges()
	var email = reg_email_edit.text.strip_edges()
	var pwd   = reg_password_edit.text.strip_edges()

	if user.is_empty():
		_show_error("Veuillez choisir un nom d'utilisateur.")
		return
	if not "@" in email or not "." in email:
		_show_error("Adresse email invalide.")
		return
	if pwd.length() < 8:
		_show_error("Le mot de passe doit contenir au moins 8 caracteres.")
		return
	if not _is_online:
		_show_error("Connexion Internet requise pour l'inscription.")
		return

	btn_register.disabled = true
	btn_register.text = "Creation du compte..."
	_show_error("")

	await get_tree().create_timer(1.2).timeout

	var user_data := {
		"username": user,
		"email":    email,
		"class":    "Guerrier",
		"level":    1,
		"token":    "tok_" + user.md5_text().left(16),
	}
	_save_local_data(user_data)
	_emit_login_success(user_data)

# ─────────────────────────────────────────────
#  4. Mode hors-ligne
# ─────────────────────────────────────────────
func _go_offline() -> void:
	# Login local sans token serveur, solo uniquement
	var user_data = _local_data.duplicate()
	user_data["offline"] = true
	_emit_login_success(user_data)

# ─────────────────────────────────────────────
#  5. Donnees locales (ConfigFile)
# ─────────────────────────────────────────────
func _load_local_data() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		_local_data = {
			"username": cfg.get_value("session", "username", ""),
			"class":    cfg.get_value("session", "class",    "Guerrier"),
			"level":    cfg.get_value("session", "level",    1),
			"token":    cfg.get_value("session", "token",    ""),
		}
	else:
		_local_data = {}

func _save_local_data(data: Dictionary) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("session", "username", data.get("username", ""))
	cfg.set_value("session", "class",    data.get("class",    "Guerrier"))
	cfg.set_value("session", "level",    data.get("level",    1))
	cfg.set_value("session", "token",    data.get("token",    ""))
	cfg.save(SAVE_PATH)

# ─────────────────────────────────────────────
#  6. Helpers UI
# ─────────────────────────────────────────────
func _set_status(text: String, color: Color) -> void:
	status_label.text  = text
	status_dot.color   = color

func _show_error(text: String) -> void:
	error_label.text = text
	btn_login.disabled    = false
	btn_login.text        = "SE CONNECTER"
	btn_register.disabled = false
	btn_register.text     = "CREER LE COMPTE"

func _emit_login_success(data: Dictionary) -> void:
	emit_signal("login_success", data)
	# Passer au menu principal
	get_tree().change_scene_to_file("res://scenes/MainUI.tscn")
