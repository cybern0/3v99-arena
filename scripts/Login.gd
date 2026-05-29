extends Control

signal login_success(user_data: Dictionary)

const SAVE_PATH  := "user://session.cfg"
const CHECK_URL  := "https://www.google.com"
const AUTO_DELAY := 1.8

@onready var status_dot      : ColorRect     = $StatusBar/StatusDot
@onready var status_label    : Label         = $StatusBar/StatusLabel
@onready var auto_panel      : VBoxContainer = $MainCard/CardVBox/AutoLoginPanel
@onready var auto_name       : Label         = $MainCard/CardVBox/AutoLoginPanel/AutoLoginName
@onready var auto_class      : Label         = $MainCard/CardVBox/AutoLoginPanel/AutoLoginClass
@onready var auto_spinner    : Label         = $MainCard/CardVBox/AutoLoginPanel/AutoLoginSpinner
@onready var btn_cancel_auto : Button        = $MainCard/CardVBox/AutoLoginPanel/BtnCancelAuto
@onready var manual_panel    : VBoxContainer = $MainCard/CardVBox/ManualLoginPanel
@onready var tab_login       : Button        = $MainCard/CardVBox/ManualLoginPanel/LoginTabRow/TabLogin
@onready var tab_register    : Button        = $MainCard/CardVBox/ManualLoginPanel/LoginTabRow/TabRegister
@onready var login_form      : VBoxContainer = $MainCard/CardVBox/ManualLoginPanel/LoginForm
@onready var register_form   : VBoxContainer = $MainCard/CardVBox/ManualLoginPanel/RegisterForm
@onready var username_edit   : LineEdit = $MainCard/CardVBox/ManualLoginPanel/LoginForm/UsernameEdit
@onready var password_edit   : LineEdit = $MainCard/CardVBox/ManualLoginPanel/LoginForm/PasswordEdit
@onready var remember_check  : CheckBox = $MainCard/CardVBox/ManualLoginPanel/LoginForm/RememberRow/RememberCheck
@onready var btn_login       : Button   = $MainCard/CardVBox/ManualLoginPanel/LoginForm/BtnLogin
@onready var reg_username_edit: LineEdit = $MainCard/CardVBox/ManualLoginPanel/RegisterForm/RegUsernameEdit
@onready var reg_email_edit  : LineEdit = $MainCard/CardVBox/ManualLoginPanel/RegisterForm/RegEmailEdit
@onready var reg_password_edit: LineEdit = $MainCard/CardVBox/ManualLoginPanel/RegisterForm/RegPasswordEdit
@onready var btn_register    : Button   = $MainCard/CardVBox/ManualLoginPanel/RegisterForm/BtnRegister
@onready var error_label     : Label    = $MainCard/CardVBox/ErrorLabel
@onready var offline_notice  : VBoxContainer = $OfflineNotice
@onready var btn_offline     : Button   = $BtnPlayOffline

# À mettre avec tes autres const
const API_URL := "https://TON_ESPACE_HUGGING_FACE.hf.space" # Remplace par ta vraie URL

# À mettre avec tes autres variables
var _http_login : HTTPRequest
var _http_register : HTTPRequest
var _http_check : HTTPRequest
var _is_online  : bool       = false
var _local_data : Dictionary = {}
var _auto_timer : SceneTreeTimer = null

func _ready() -> void:
	# --- NOUVEAU : Initialisation des requêtes HTTP ---
	_http_login = HTTPRequest.new()
	add_child(_http_login)
	_http_login.request_completed.connect(_on_login_request_completed)
	
	_http_register = HTTPRequest.new()
	add_child(_http_register)
	_http_register.request_completed.connect(_on_register_request_completed)
	# --------------------------------------------------

	_connect_signals()
	_load_local_data()
	_check_connection()

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

	# Préparation de la requête vers FastAPI
	var url = API_URL + "/get_player_api_key"
	var headers = ["Content-Type: application/json"]
	var body = JSON.stringify({"name": user, "password": pwd})
	
	_http_login.request(url, headers, HTTPClient.METHOD_POST, body)

func _on_login_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	btn_login.disabled = false
	btn_login.text     = "SE CONNECTER"
	
	if result != HTTPRequest.RESULT_SUCCESS:
		_show_error("Impossible de joindre le serveur.")
		return
		
	var json = JSON.parse_string(body.get_string_from_utf8())
	
	if response_code == 200 and json != null:
		# Succès : on récupère la vraie clé API de la base de données
		var user_data := {
			"username": username_edit.text.strip_edges(),
			"class":    "Guerrier",
			"level":    1,
			"token":    json.get("api_key", ""), # On remplace le faux MD5 par la vraie clé API
		}
		
		if remember_check.button_pressed:
			_save_local_data(user_data)
			
		_emit_login_success(user_data)
	else:
		# Erreur 401 (Mauvais mot de passe) ou autre
		var error_msg = json.get("detail", "Identifiants incorrects.") if json else "Erreur serveur."
		_show_error(error_msg)

func _on_register_pressed() -> void:
	var user  := reg_username_edit.text.strip_edges()
	var email := reg_email_edit.text.strip_edges()
	var pwd   := reg_password_edit.text.strip_edges()
	
	if user.is_empty():
		_show_error("Veuillez choisir un nom d'utilisateur."); return
	if not "@" in email or not "." in email:
		_show_error("Adresse email invalide."); return
	if pwd.length() < 8:
		_show_error("Le mot de passe doit contenir au moins 8 caractères."); return
	if not _is_online:
		_show_error("Connexion Internet requise pour l'inscription."); return

	btn_register.disabled = true
	btn_register.text     = "Création du compte..."
	error_label.text      = ""

	# L'API s'attend à recevoir "name" et "password" selon ton schéma Pydantic UserAuth
	var url = API_URL + "/signup"
	var headers = ["Content-Type: application/json"]
	var body = JSON.stringify({"name": user, "password": pwd})
	
	_http_register.request(url, headers, HTTPClient.METHOD_POST, body)

func _on_register_request_completed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	btn_register.disabled = false
	btn_register.text     = "CRÉER LE COMPTE"
	
	if result != HTTPRequest.RESULT_SUCCESS:
		_show_error("Impossible de joindre le serveur.")
		return
		
	var json = JSON.parse_string(body.get_string_from_utf8())
	
	if response_code == 201 and json != null: # 201 = HTTP_201_CREATED défini dans ton FastAPI
		var user_data := {
			"username": reg_username_edit.text.strip_edges(),
			"class":    "Guerrier",
			"level":    1,
			"token":    json.get("api_key", ""),
		}
		_save_local_data(user_data)
		_emit_login_success(user_data)
	else:
		# Erreur 400 (Nom d'utilisateur déjà pris par exemple)
		var error_msg = json.get("detail", "Erreur lors de l'inscription.") if json else "Erreur serveur."
		_show_error(error_msg)

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
#  Connexion Internet
# ─────────────────────────────────────────────
func _check_connection() -> void:
	_set_status("Vérification de la connexion...", Color(0.95, 0.82, 0.35, 0.9))
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
	_set_status("Connecté à Internet", Color(0.35, 0.9, 0.55, 1.0))
	if not _local_data.is_empty() and _local_data.has("username"):
		_show_auto_login()
	else:
		_show_manual_login()

func _on_connection_failed() -> void:
	_is_online = false
	_set_status("Hors ligne", Color(0.95, 0.42, 0.32, 1.0))
	offline_notice.visible = true
	if not _local_data.is_empty() and _local_data.has("username"):
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
	auto_name.text  = _local_data.get("username", "Joueur")
	auto_class.text = _local_data.get("class", "Guerrier") + "  •  Niveau " + str(_local_data.get("level", 1))
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

	await get_tree().create_timer(1.0).timeout
	if not is_inside_tree():
		return

	var user_data := {
		"username": user,
		"class":    "Guerrier",
		"level":    1,
		"token":    "tok_" + user.md5_text().left(16),
	}
	if remember_check.button_pressed:
		_save_local_data(user_data)

	# ── FIX : rétablir le bouton avant de quitter la scène ───────────────────
	btn_login.disabled = false
	btn_login.text     = "SE CONNECTER"
	_emit_login_success(user_data)

func _on_register_pressed() -> void:
	var user  := reg_username_edit.text.strip_edges()
	var email := reg_email_edit.text.strip_edges()
	var pwd   := reg_password_edit.text.strip_edges()
	if user.is_empty():
		_show_error("Veuillez choisir un nom d'utilisateur."); return
	if not "@" in email or not "." in email:
		_show_error("Adresse email invalide."); return
	if pwd.length() < 8:
		_show_error("Le mot de passe doit contenir au moins 8 caractères."); return
	if not _is_online:
		_show_error("Connexion Internet requise pour l'inscription."); return

	btn_register.disabled = true
	btn_register.text     = "Création du compte..."
	error_label.text      = ""

	await get_tree().create_timer(1.2).timeout
	if not is_inside_tree():
		return

	var user_data := {
		"username": user,
		"email":    email,
		"class":    "Guerrier",
		"level":    1,
		"token":    "tok_" + user.md5_text().left(16),
	}
	_save_local_data(user_data)
	btn_register.disabled = false
	btn_register.text     = "CRÉER LE COMPTE"
	_emit_login_success(user_data)

# ─────────────────────────────────────────────
#  Mode hors-ligne
# ─────────────────────────────────────────────
func _go_offline() -> void:
	var user_data := _local_data.duplicate()
	user_data["offline"] = true
	_emit_login_success(user_data)

# ─────────────────────────────────────────────
#  Données locales
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
#  Helpers UI
# ─────────────────────────────────────────────
func _set_status(text: String, color: Color) -> void:
	status_label.text = text
	status_dot.color  = color

# ── FIX : _show_error ne reset QUE le bouton du formulaire actif ─────────────
func _show_error(text: String) -> void:
	error_label.text = text
	if login_form.visible:
		btn_login.disabled = false
		btn_login.text     = "SE CONNECTER"
	else:
		btn_register.disabled = false
		btn_register.text     = "CRÉER LE COMPTE"

func _emit_login_success(data: Dictionary) -> void:
	# ── FIX : syntaxe Godot 4 ────────────────────────────────────────────────
	login_success.emit(data)
	get_tree().change_scene_to_file("res://scenes/MainUI.tscn")
