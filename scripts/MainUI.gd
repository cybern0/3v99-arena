extends Control

# ── Couleurs armure ────────────────────────────────────────────────────────────
const ARMOR_COLORS := {
	"Violet": Color(0.25, 0.20, 0.65, 1.0),
	"Bleu":   Color(0.12, 0.30, 0.80, 1.0),
	"Rouge":  Color(0.70, 0.10, 0.10, 1.0),
	"Or":     Color(0.72, 0.55, 0.08, 1.0),
}

# ── Stats par classe ───────────────────────────────────────────────────────────
const CLASS_STATS := {
	"Guerrier": {"vie": 80, "atq": 70, "def": 75, "vit": 55},
	"Mage":     {"vie": 55, "atq": 95, "def": 40, "vit": 65},
	"Archer":   {"vie": 65, "atq": 80, "def": 50, "vit": 85},
	"Assassin": {"vie": 60, "atq": 90, "def": 45, "vit": 90},
}

# ── Noeuds principaux ──────────────────────────────────────────────────────────
@onready var main_menu : Control = $MainMenuScreen
@onready var avatar_scr: Control = $AvatarScreen
@onready var solo_scr  : Control = $SoloScreen
@onready var br_scr    : Control = $BattleRoyalScreen   # ← devient "Créer Room Boss"
@onready var bh_scr    : Control = $BossHuntScreen

# Avatar 3D → remplacé par images 2D
const MODEL_SCENES := {
	"Model 1": preload("res://scenes/P1.tscn"),
	"Model 2": preload("res://scenes/P2.tscn"),
}

# Images 2D pour l'aperçu dans l'UI
const MODEL_IMAGES := {
	"Model 1": preload("res://assets/P1/P1Pose.jpg"),
	"Model 2": preload("res://assets/P2/P2Pose.jpg"),
}

# Plus de viewport 3D, on utilise des images 2D
# var char_node  : Node3D
# var avatar_cam : Camera3D

@onready var name_edit  : LineEdit      = $AvatarScreen/AvatarControls/NameEdit
@onready var stat_vie   : ProgressBar   = $AvatarScreen/AvatarControls/StatsGrid/BarVie
@onready var stat_atq   : ProgressBar   = $AvatarScreen/AvatarControls/StatsGrid/BarAtq
@onready var stat_def   : ProgressBar   = $AvatarScreen/AvatarControls/StatsGrid/BarDef
@onready var stat_vit   : ProgressBar   = $AvatarScreen/AvatarControls/StatsGrid/BarVit
# AvatarImage est maintenant dans AvatarScreen
@onready var avatar_preview_img : TextureRect = $AvatarScreen/AvatarPreview

# Solo — aperçu
@onready var prev_map   : Label = $SoloScreen/SoloContent/SoloRightPanel/PreviewCard/PreviewVBox/PrevMapVal
@onready var prev_time  : Label = $SoloScreen/SoloContent/SoloRightPanel/PreviewCard/PreviewVBox/PrevTimeVal
@onready var prev_meteo : Label = $SoloScreen/SoloContent/SoloRightPanel/PreviewCard/PreviewVBox/PrevMeteoVal
@onready var prev_diff  : Label = $SoloScreen/SoloContent/SoloRightPanel/PreviewCard/PreviewVBox/PrevDiffVal
@onready var prev_cam   : Label = $SoloScreen/SoloContent/SoloRightPanel/PreviewCard/PreviewVBox/PrevCamVal

# "Créer Room Boss" — aperçu (nœuds renommés dans le TSCN)
@onready var boss_prev_boss   : Label = $BattleRoyalScreen/BRContent/BRRight/BossPreviewCard/BossPreviewVBox/PrevBossVal
@onready var boss_prev_map    : Label = $BattleRoyalScreen/BRContent/BRRight/BossPreviewCard/BossPreviewVBox/PrevBRMapVal
@onready var boss_prev_players: Label = $BattleRoyalScreen/BRContent/BRRight/BossPreviewCard/BossPreviewVBox/PrevMaxPlayersVal
@onready var boss_room_code   : Label = $BattleRoyalScreen/BRContent/BRRight/RoomCodeVal

# Map → scène
const MAP_SCENES := {
	"Foret Profonde": "res://scenes/w_1.tscn",
	"Desert Aride":   "res://scenes/w_2.tscn",
	"Montagne Glace": "res://scenes/w_3.tscn",
}

# ── État interne ───────────────────────────────────────────────────────────────
var _rot_dir:        float   = 1.0
var _current_class:  String  = "Guerrier"
var _selected_model: String  = "Model 1"

var _solo_config: Dictionary = {
	"map":    "Foret Profonde",
	"time":   "Jour",
	"meteo":  "Ensoleille",
	"diff":   "Normal",
	"camera": "TPS",
}

var _boss_config: Dictionary = {
	"boss":        "Dragon de Feu Eternel",
	"map":         "Desert Aride",
	"max_players": 4,
	"room_name":   "",
}

# ── Référence au modèle Player instancié dans la scène de jeu ─────────────────
# MainUI stocke la sélection dans SessionManager ; la scène de jeu appelle ensuite
# player_node.create_mobile_controls() après avoir instancié le bon modèle.
var _active_player_model: Node = null  # rempli si un Player est présent dans cette scène

# ══════════════════════════════════════════════════════════════════════════════
func _ready() -> void:
	_connect_all()
	_select_model("Model 1")
	_show(main_menu)

# ── Connexion des signaux ──────────────────────────────────────────────────────
func _connect_all() -> void:
	# Menu principal
	$MainMenuScreen/MenuButtons/BtnAvatar.pressed.connect(func(): _show(avatar_scr))
	$MainMenuScreen/MenuButtons/BtnSolo.pressed.connect(func(): _show(solo_scr))
	# BtnBattleRoyal renommé "Créer Room Boss" dans le TSCN — ouvre br_scr
	$MainMenuScreen/MenuButtons/BtnBattleRoyal.pressed.connect(func(): _show(br_scr))
	$MainMenuScreen/MenuButtons/BtnBossHunt.pressed.connect(func(): _show(bh_scr))

	# ── AVATAR ────────────────────────────────────────────────────────────────
	$AvatarScreen/AvatarHeader/BtnBackAvatar.pressed.connect(func(): _show(main_menu))
	$AvatarScreen/AvatarControls/BtnSaveAvatar.pressed.connect(_save_avatar)
	# Rotation désactivée car on utilise des images 2D statiques
	# $AvatarScreen/AvatarControls/RotateRow/BtnRotL.pressed.connect(func(): _manual_rotate(-0.4))
	# $AvatarScreen/AvatarControls/RotateRow/BtnRotR.pressed.connect(func(): _manual_rotate( 0.4))

	for btn in $AvatarScreen/AvatarControls/ClassRow.get_children():
		btn.pressed.connect(_on_class_selected.bind(btn.text))

	$AvatarScreen/AvatarControls/ModelRow/BtnModel1.pressed.connect(func(): _select_model("Model 1"))
	$AvatarScreen/AvatarControls/ModelRow/BtnModel2.pressed.connect(func(): _select_model("Model 2"))

	for btn in $AvatarScreen/AvatarControls/ColorRow.get_children():
		btn.pressed.connect(_on_color_selected.bind(btn.text))

	# ── SOLO ──────────────────────────────────────────────────────────────────
	$SoloScreen/SoloHeader/BtnBackSolo.pressed.connect(func(): _show(main_menu))
	$SoloScreen/SoloContent/SoloLeftPanel/BtnLancer.pressed.connect(_launch_solo)
	$SoloScreen/SoloContent/SoloLeftPanel/MapOption.item_selected.connect(_on_map_selected)

	_connect_toggle_group(
		$SoloScreen/SoloContent/SoloLeftPanel/TimeRow.get_children(),
		func(t): _solo_config["time"] = t; prev_time.text = t
	)
	_connect_toggle_group(
		$SoloScreen/SoloContent/SoloLeftPanel/MeteoRow.get_children(),
		func(t): _solo_config["meteo"] = t; prev_meteo.text = t
	)
	_connect_toggle_group(
		$SoloScreen/SoloContent/SoloLeftPanel/DiffRow.get_children(),
		func(t): _solo_config["diff"] = t; prev_diff.text = t
	)
	_connect_toggle_group(
		$SoloScreen/SoloContent/SoloRightPanel/CamRow.get_children(),
		func(t):
			_solo_config["camera"] = "TPS" if t == "TPS — 3e pers." else "FPS"
			_update_cam_preview()
	)

	# ── CRÉER ROOM BOSS (ancien BattleRoyalScreen) ────────────────────────────
	$BattleRoyalScreen/BRHeader/BtnBackBR.pressed.connect(func(): _show(main_menu))
	$BattleRoyalScreen/BRContent/BRLeft/BtnCreateBoss.pressed.connect(_create_boss_room)

	# Boss sélection
	$BattleRoyalScreen/BRContent/BRLeft/BossOption.item_selected.connect(_on_boss_selected)
	# Map sélection dans l'écran boss
	$BattleRoyalScreen/BRContent/BRLeft/BRMapOption.item_selected.connect(_on_boss_map_selected)
	# Max players
	_connect_toggle_group(
		$BattleRoyalScreen/BRContent/BRLeft/MaxPlayersRow.get_children(),
		func(t): _boss_config["max_players"] = int(t); _update_boss_preview()
	)

	# ── BOSS HUNT ─────────────────────────────────────────────────────────────
	$BossHuntScreen/BHHeader/BtnBackBH.pressed.connect(func(): _show(main_menu))
	$BossHuntScreen/BHContent/BHLeft/BtnJoinBH.pressed.connect(_join_bh)

	for row in $BossHuntScreen/BHContent/BHRight/BHPlayerScroll/BHPlayerList.get_children():
		var btn  = row.get_node_or_null("Btn")
		var name = row.get_node_or_null("Name")
		if btn and name:
			btn.pressed.connect(_invite.bind(name.text))

# ══════════════════════════════════════════════════════════════════════════════
#  Navigation
# ══════════════════════════════════════════════════════════════════════════════
func _show(screen: Control) -> void:
	for s in [main_menu, avatar_scr, solo_scr, br_scr, bh_scr]:
		s.visible = (s == screen)

# ══════════════════════════════════════════════════════════════════════════════
#  Avatar 2D (plus de 3D)
# ══════════════════════════════════════════════════════════════════════════════
# Fonctions désactivées car on utilise des images 2D statiques
# func _manual_rotate(amount: float) -> void:
# 	char_node.rotate_y(amount)

func _on_class_selected(cls: String) -> void:
	_current_class = cls
	if cls in CLASS_STATS:
		var s = CLASS_STATS[cls]
		stat_vie.value = s["vie"]
		stat_atq.value = s["atq"]
		stat_def.value = s["def"]
		stat_vit.value = s["vit"]

func _on_color_selected(color_name: String) -> void:
	# Couleur désactivée car on utilise des images 2D statiques
	pass

# Fonctions désactivées
# func _apply_armor_color(node: Node, color: Color) -> void:
# 	if node is MeshInstance3D:
# 		var mesh_node := node as MeshInstance3D
# 		if mesh_node.mesh:
# 			for surface in range(mesh_node.mesh.get_surface_count()):
# 				var mat := mesh_node.get_surface_override_material(surface)
# 				if mat == null:
# 					mat = mesh_node.mesh.surface_get_material(surface)
# 				if mat and mat is StandardMaterial3D:
# 					var new_mat := mat.duplicate() as StandardMaterial3D
# 					new_mat.albedo_color = color
# 					mesh_node.set_surface_override_material(surface, new_mat)
# 	for child in node.get_children():
# 		_apply_armor_color(child, color)

func _save_avatar() -> void:
	var nom := name_edit.text.strip_edges()
	if nom.is_empty():
		nom = "Joueur"
	$MainMenuScreen/AvatarCard/AvatarVBox/AvatarNameLabel.text = nom
	$MainMenuScreen/AvatarCard/AvatarVBox/AvatarClassLabel.text = _current_class + "  |  Niveau 1"
	_show(main_menu)

func _select_model(model_name: String) -> void:
	if not MODEL_SCENES.has(model_name):
		return
	_selected_model = model_name
	
	# Afficher l'image 2D correspondante
	if avatar_preview_img and MODEL_IMAGES.has(model_name):
		avatar_preview_img.texture = MODEL_IMAGES[model_name]
		avatar_preview_img.visible = true
		# S'assurer que l'image garde ses proportions et s'adapte au container
		avatar_preview_img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		avatar_preview_img.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	
	# Stocker la référence si le modèle est un Player (pour la logique de création de HUD)
	_active_player_model = null  # Sera réinstancié dans la scène de jeu
	
	for btn in $AvatarScreen/AvatarControls/ModelRow.get_children():
		if btn is Button:
			btn.set_pressed(btn.text == model_name)

# Fonctions désactivées
# func _attach_camera_to_model(model: Node3D) -> void:
# 	var cam_offset := Vector3(0, 1.2, 2.5)
# 	avatar_cam.transform.origin = model.to_global(cam_offset)
# 	avatar_cam.look_at(model.global_transform.origin + Vector3(0, 0.8, 0))

# func _play_default_animation(node: Node) -> void:
# 	var anim_player := node.get_node_or_null("AnimationPlayer")
# 	if anim_player == null:
# 		anim_player = node.find_child("AnimationPlayer", true, false) as AnimationPlayer
# 	if anim_player:
# 		var animations: Array = anim_player.get_animation_list()
# 		if animations.size() > 0:
# 			var animation_name: String = "idle" if animations.has("idle") else animations[0]
# 			var animation: Animation = anim_player.get_animation(animation_name)
# 			if animation:
# 				animation.loop_mode = Animation.LOOP_LINEAR
# 				anim_player.play(animation_name)

# ══════════════════════════════════════════════════════════════════════════════
#  Solo
# ══════════════════════════════════════════════════════════════════════════════
func _on_map_selected(index: int) -> void:
	var map_name: String = $SoloScreen/SoloContent/SoloLeftPanel/MapOption.get_item_text(index)
	_solo_config["map"] = map_name
	prev_map.text = map_name

func _update_cam_preview() -> void:
	prev_cam.text = "TPS — 3e personne" if _solo_config["camera"] == "TPS" else "FPS — 1re personne"

func _launch_solo() -> void:
	# ── Configuration du SessionManager pour la scène de jeu ──────────────────
	# C'est la scène de jeu qui lira ces valeurs et appellera
	# player_node.create_mobile_controls() dans son _ready() ou après l'instanciation.
	if has_node("/root/SessionManager"):
		var sm = get_node("/root/SessionManager")
		sm.solo_config     = _solo_config.duplicate()
		sm.selected_model  = _selected_model
		sm.needs_mobile_hud = true   # ← lu par la scène de jeu
	
	print("[Solo] Lancement — config: ", _solo_config, " | modèle: ", _selected_model)
	var map_name:   String = _solo_config["map"]
	var scene_path: String = MAP_SCENES.get(map_name, "res://scenes/w_1.tscn")
	print("[Solo] Scène cible: ", scene_path)
	get_tree().change_scene_to_file(scene_path)

# ══════════════════════════════════════════════════════════════════════════════
#  Créer Room Boss (ancien "Battle Royal")
# ══════════════════════════════════════════════════════════════════════════════
func _on_boss_selected(index: int) -> void:
	var boss_name: String = $BattleRoyalScreen/BRContent/BRLeft/BossOption.get_item_text(index)
	_boss_config["boss"] = boss_name
	_update_boss_preview()

func _on_boss_map_selected(index: int) -> void:
	var map_name: String = $BattleRoyalScreen/BRContent/BRLeft/BRMapOption.get_item_text(index)
	_boss_config["map"] = map_name
	_update_boss_preview()

func _update_boss_preview() -> void:
	if boss_prev_boss:
		boss_prev_boss.text = _boss_config["boss"]
	if boss_prev_map:
		boss_prev_map.text = _boss_config["map"]
	if boss_prev_players:
		boss_prev_players.text = str(_boss_config["max_players"]) + " joueurs max"

func _create_boss_room() -> void:
	# Récupérer le nom de room saisi
	var room_name_edit = $BattleRoyalScreen/BRContent/BRLeft/RoomNameEdit
	var room_name: String = room_name_edit.text.strip_edges() if room_name_edit else ""
	if room_name.is_empty():
		room_name = "Room-Boss-" + str(randi() % 9000 + 1000)
	_boss_config["room_name"] = room_name

	# Générer un code de room
	var room_code: String = _generate_room_code()
	if boss_room_code:
		boss_room_code.text = room_code

	print("[Boss Room] Création — config: ", _boss_config, " | code: ", room_code)

	# Transmettre la config au SessionManager
	if has_node("/root/SessionManager"):
		var sm = get_node("/root/SessionManager")
		sm.boss_config      = _boss_config.duplicate()
		sm.selected_model   = _selected_model
		sm.needs_mobile_hud = true
		sm.room_code        = room_code
		sm.is_host          = true

	# Lancer la scène Boss Hunt correspondante
	var scene_path := "res://scenes/boss_hunt.tscn"
	if ResourceLoader.exists(scene_path):
		get_tree().change_scene_to_file(scene_path)
	else:
		print("[Boss Room] Scène boss_hunt.tscn introuvable — config sauvegardée.")

func _generate_room_code() -> String:
	const CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var code := ""
	for i in range(6):
		code += CHARS[randi() % CHARS.length()]
	return code

# ══════════════════════════════════════════════════════════════════════════════
#  Boss Hunt — Joindre (inchangé)
# ══════════════════════════════════════════════════════════════════════════════
func _join_bh() -> void:
	var code: String   = $BossHuntScreen/BHContent/BHLeft/SearchBHEdit.text.strip_edges()
	var list: ItemList = $BossHuntScreen/BHContent/BHLeft/BHRoomsList
	var sel: Array     = list.get_selected_items()
	if code.is_empty() and sel.is_empty():
		print("[BH] Sélectionnez une room ou entrez un code.")
		return
	var room: String = code if not code.is_empty() else list.get_item_text(sel[0])
	print("[BH] Rejoindre: ", room)

# ══════════════════════════════════════════════════════════════════════════════
#  Inviter un joueur
# ══════════════════════════════════════════════════════════════════════════════
func _invite(player_name: String) -> void:
	print("[Invite] Invitation envoyée à: ", player_name)

# ══════════════════════════════════════════════════════════════════════════════
#  Helper — groupe de boutons toggle (un seul actif)
# ══════════════════════════════════════════════════════════════════════════════
func _connect_toggle_group(buttons: Array, callback: Callable) -> void:
	for btn in buttons:
		btn.pressed.connect(func():
			for b in buttons:
				b.button_pressed = (b == btn)
			callback.call(btn.text)
		)
