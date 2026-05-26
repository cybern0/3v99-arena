# SessionManager.gd
# Attacher sur un Autoload (singleton) : Projet > Parametres > Autoload
# Nom : SessionManager
extends Node

# ─────────────────────────────────────────────
#  Etat global de session (accessible partout)
# ─────────────────────────────────────────────
var is_logged_in  : bool       = false
var is_online     : bool       = false
var user_data     : Dictionary = {}

# Configuration du mode solo
var solo_config    : Dictionary = {}
var selected_model : String     = "Model 1"

# Flag pour indiquer si le HUD mobile doit être affiché en mode solo
var needs_mobile_hud : bool = false

# ─────────────────────────────────────────────
#  Appeler depuis MainUI avant d'ouvrir BR/BH
# ─────────────────────────────────────────────
func require_login(origin_scene: Node) -> bool:
	"""
	Retourne true si l'utilisateur est connecte.
	Sinon redirige vers Login et retourne false.
	"""
	if is_logged_in and is_online:
		return true

	# Sauvegarder la scene d'origine pour y revenir apres login
	# (optionnel : passer via un signal ou une variable globale)
	origin_scene.get_tree().change_scene_to_file("res://scenes/Login.tscn")
	return false

func login(data: Dictionary, online: bool) -> void:
	user_data    = data
	is_logged_in = true
	is_online    = online

func logout() -> void:
	# Supprimer le fichier session
	var path := ProjectSettings.globalize_path("user://session.cfg")
	if FileAccess.file_exists("user://session.cfg"):
		DirAccess.remove_absolute(path)
	user_data    = {}
	is_logged_in = false
	is_online    = false
