## SessionManager.gd
## Autoload singleton — Projet > Parametres > Autoload > Nom : SessionManager
extends Node

# ─────────────────────────────────────────────
#  Etat global de session
# ─────────────────────────────────────────────
var is_logged_in  : bool       = false
var is_online     : bool       = false
var user_data     : Dictionary = {}

## Identifiant base de donnees du joueur (p_id Supabase)
var p_id          : int        = -1

## Stats actuelles (agility / strength / vitality / shield)
var stats         : Dictionary = {}

## Points disponibles non encore alloues
var available_pts : int        = 0
var total_pts     : int        = 0

## Stats en attente d'envoi si le joueur etait offline lors de l'allocation
var pending_stats_update : Dictionary = {}
var has_pending_stats    : bool       = false

# Configuration du mode de jeu
var solo_config    : Dictionary = {}
var selected_model : String     = "Model 1"  # "Model 1" = P1 (masc), "Model 2" = P2 (fem)
var needs_mobile_hud : bool     = false

# Fichier de sauvegarde locale
const SAVE_PATH := "user://session.cfg"

# ─────────────────────────────────────────────
#  Login / Logout
# ─────────────────────────────────────────────
func login(data: Dictionary, online: bool) -> void:
	user_data    = data.duplicate(true)
	is_logged_in = true
	is_online    = online

	# Extraction du p_id si presente dans les donnees (vient de FastAPI)
	if data.has("p_id"):
		p_id = int(data["p_id"])

	# Extraction du profil stats si present
	if data.has("stats") and typeof(data["stats"]) == TYPE_DICTIONARY:
		stats = data["stats"].duplicate(true)
	if data.has("available_pts"):
		available_pts = int(data["available_pts"])
	if data.has("total_pts"):
		total_pts = int(data["total_pts"])


func logout() -> void:
	var cfg_path := "user://session.cfg"
	if FileAccess.file_exists(cfg_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(cfg_path))
	user_data         = {}
	p_id              = -1
	stats             = {}
	available_pts     = 0
	total_pts         = 0
	pending_stats_update = {}
	has_pending_stats = false
	is_logged_in      = false
	is_online         = false
	selected_model    = "Model 1"


## Retourne true si connecte, sinon redirige vers Login
func require_login(origin_scene: Node) -> bool:
	if is_logged_in:
		return true
	origin_scene.get_tree().change_scene_to_file("res://scenes/Login.tscn")
	return false


# ─────────────────────────────────────────────
#  Gestion stats offline-first
# ─────────────────────────────────────────────

## Mise a jour locale des stats (appelee depuis CharacterScreen)
func apply_stats_locally(new_stats: Dictionary) -> void:
	stats = new_stats.duplicate(true)
	var allocated := 0
	for v in stats.values():
		allocated += int(v)
	available_pts = max(total_pts - allocated, 0)
	_save_local_data()


## Marque des stats comme "a envoyer au prochain login en ligne"
func queue_stats_for_sync(new_stats: Dictionary) -> void:
	pending_stats_update = new_stats.duplicate(true)
	has_pending_stats    = true
	apply_stats_locally(new_stats)


## Retourne true si des stats sont en attente d'envoi
func has_pending_sync() -> bool:
	return has_pending_stats and not pending_stats_update.is_empty()


## Appele par Login.gd apres connexion reussie si has_pending_sync()
func consume_pending_stats() -> Dictionary:
	var to_send := pending_stats_update.duplicate(true)
	pending_stats_update = {}
	has_pending_stats    = false
	_save_local_data()
	return to_send


# ─────────────────────────────────────────────
#  Persistance locale (ConfigFile)
# ─────────────────────────────────────────────
func save_session(data: Dictionary) -> void:
	_save_local_data()


func _save_local_data() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("session", "username",   user_data.get("username",   ""))
	cfg.set_value("session", "class",      user_data.get("class",      "Guerrier"))
	cfg.set_value("session", "level",      user_data.get("level",      1))
	cfg.set_value("session", "token",      user_data.get("token",      ""))
	cfg.set_value("session", "p_id",       p_id)
	cfg.set_value("session", "total_pts",  total_pts)

	# Stats actuelles
	cfg.set_value("stats", "agility",  stats.get("agility",  0))
	cfg.set_value("stats", "strength", stats.get("strength", 0))
	cfg.set_value("stats", "vitality", stats.get("vitality", 0))
	cfg.set_value("stats", "shield",   stats.get("shield",   0))
	cfg.set_value("stats", "available_pts", available_pts)

	# Stats en attente
	cfg.set_value("pending", "has_pending", has_pending_stats)
	if has_pending_stats:
		cfg.set_value("pending", "agility",  pending_stats_update.get("agility",  0))
		cfg.set_value("pending", "strength", pending_stats_update.get("strength", 0))
		cfg.set_value("pending", "vitality", pending_stats_update.get("vitality", 0))
		cfg.set_value("pending", "shield",   pending_stats_update.get("shield",   0))

	cfg.save(SAVE_PATH)


func load_local_data() -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return {}

	var data := {
		"username":   cfg.get_value("session", "username",   ""),
		"class":      cfg.get_value("session", "class",      "Guerrier"),
		"level":      cfg.get_value("session", "level",      1),
		"token":      cfg.get_value("session", "token",      ""),
		"p_id":       cfg.get_value("session", "p_id",       -1),
		"total_pts":  cfg.get_value("session", "total_pts",  0),
		"stats": {
			"agility":  cfg.get_value("stats", "agility",  0),
			"strength": cfg.get_value("stats", "strength", 0),
			"vitality": cfg.get_value("stats", "vitality", 0),
			"shield":   cfg.get_value("stats", "shield",   0),
		},
		"available_pts": cfg.get_value("stats", "available_pts", 0),
	}

	# Restaurer stats en attente
	has_pending_stats = bool(cfg.get_value("pending", "has_pending", false))
	if has_pending_stats:
		pending_stats_update = {
			"agility":  cfg.get_value("pending", "agility",  0),
			"strength": cfg.get_value("pending", "strength", 0),
			"vitality": cfg.get_value("pending", "vitality", 0),
			"shield":   cfg.get_value("pending", "shield",   0),
		}

	return data


# ─────────────────────────────────────────────
#  Helpers
# ─────────────────────────────────────────────

## Retourne le token (api_key) de l'utilisateur
func get_token() -> String:
	return String(user_data.get("token", ""))

## Retourne le nom d'utilisateur
func get_username() -> String:
	return String(user_data.get("username", "Joueur"))
