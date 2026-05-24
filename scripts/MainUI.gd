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
@onready var main_menu    : Control = $MainMenuScreen
@onready var avatar_scr   : Control = $AvatarScreen
@onready var solo_scr     : Control = $SoloScreen
@onready var br_scr       : Control = $BattleRoyalScreen
@onready var bh_scr       : Control = $BossHuntScreen

# Avatar 3D
const MODEL_SCENES := {
	"Model 1": preload("res://scenes/P1.tscn"),
	"Model 2": preload("res://scenes/P2.tscn"),
}

@onready var char_node    : Node3D          = $AvatarScreen/AvatarViewportContainer/AvatarViewport/CharNode
@onready var avatar_cam   : Camera3D         = $AvatarScreen/AvatarViewportContainer/AvatarViewport/AvatarCamera
@onready var rot_timer    : Timer           = $AvatarScreen/AvatarViewportContainer/AvatarViewport/AvatarRotateTimer
@onready var name_edit    : LineEdit        = $AvatarScreen/AvatarControls/NameEdit
@onready var stat_vie     : ProgressBar     = $AvatarScreen/AvatarControls/StatsGrid/BarVie
@onready var stat_atq     : ProgressBar     = $AvatarScreen/AvatarControls/StatsGrid/BarAtq
@onready var stat_def     : ProgressBar     = $AvatarScreen/AvatarControls/StatsGrid/BarDef
@onready var stat_vit     : ProgressBar     = $AvatarScreen/AvatarControls/StatsGrid/BarVit

# Solo — apercu
@onready var prev_map     : Label = $SoloScreen/SoloContent/SoloRightPanel/PreviewCard/PreviewVBox/PrevMapVal
@onready var prev_time    : Label = $SoloScreen/SoloContent/SoloRightPanel/PreviewCard/PreviewVBox/PrevTimeVal
@onready var prev_meteo   : Label = $SoloScreen/SoloContent/SoloRightPanel/PreviewCard/PreviewVBox/PrevMeteoVal
@onready var prev_diff    : Label = $SoloScreen/SoloContent/SoloRightPanel/PreviewCard/PreviewVBox/PrevDiffVal
@onready var prev_cam     : Label = $SoloScreen/SoloContent/SoloRightPanel/PreviewCard/PreviewVBox/PrevCamVal

# Map vers scene
const MAP_SCENES := {
	"Foret Profonde": "res://scenes/w_1.tscn",
	"Desert Aride":   "res://scenes/w_2.tscn",
	"Montagne Glace": "res://scenes/w_3.tscn",
}

# ── Etat interne ───────────────────────────────────────────────────────────────
var _rot_dir       : float  = 1.0
var _current_class : String = "Guerrier"
var _selected_model: String = "Model 1"
var _solo_config   : Dictionary = {
	"map":    "Foret Profonde",
	"time":   "Jour",
	"meteo":  "Ensoleille",
	"diff":   "Normal",
	"camera": "TPS",
}

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
	$MainMenuScreen/MenuButtons/BtnBattleRoyal.pressed.connect(func(): _show(br_scr))
	$MainMenuScreen/MenuButtons/BtnBossHunt.pressed.connect(func(): _show(bh_scr))

	# ── AVATAR ────────────────────────────────────────────────────────────────
	$AvatarScreen/AvatarHeader/BtnBackAvatar.pressed.connect(func(): _show(main_menu))
	$AvatarScreen/AvatarControls/BtnSaveAvatar.pressed.connect(_save_avatar)

	# Rotation manuelle
	$AvatarScreen/AvatarControls/RotateRow/BtnRotL.pressed.connect(func(): _manual_rotate(-0.4))
	$AvatarScreen/AvatarControls/RotateRow/BtnRotR.pressed.connect(func(): _manual_rotate(0.4))

	# Classe
	for btn in $AvatarScreen/AvatarControls/ClassRow.get_children():
		btn.pressed.connect(_on_class_selected.bind(btn.text))

	# Modele de personnage
	$AvatarScreen/AvatarControls/ModelRow/BtnModel1.pressed.connect(func(): _select_model("Model 1"))
	$AvatarScreen/AvatarControls/ModelRow/BtnModel2.pressed.connect(func(): _select_model("Model 2"))

	# Couleur armure
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
			if t == "TPS — 3e pers.":
				_solo_config["camera"] = t
			else:
				_solo_config["camera"] = "FPS"
			_update_cam_preview()
	)

	# ── BATTLE ROYAL ──────────────────────────────────────────────────────────
	$BattleRoyalScreen/BRHeader/BtnBackBR.pressed.connect(func(): _show(main_menu))
	$BattleRoyalScreen/BRContent/BRLeft/BtnJoinBR.pressed.connect(_join_br)

	for row in $BattleRoyalScreen/BRContent/BRRight/BRPlayerScroll/BRPlayerList.get_children():
		var btn  = row.get_node_or_null("Btn")
		var name = row.get_node_or_null("Name")
		if btn and name:
			btn.pressed.connect(_invite.bind(name.text))

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
#  Avatar 3D
# ══════════════════════════════════════════════════════════════════════════════
func _manual_rotate(amount: float) -> void:
	char_node.rotate_y(amount)

func _on_class_selected(cls: String) -> void:
	_current_class = cls
	if cls in CLASS_STATS:
		var s = CLASS_STATS[cls]
		stat_vie.value = s["vie"]
		stat_atq.value = s["atq"]
		stat_def.value = s["def"]
		stat_vit.value = s["vit"]

func _on_color_selected(color_name: String) -> void:
	if color_name in ARMOR_COLORS:
		_apply_armor_color(char_node, ARMOR_COLORS[color_name])

func _apply_armor_color(node: Node, color: Color) -> void:
	if node is MeshInstance3D:
		var mesh_node := node as MeshInstance3D
		if mesh_node.mesh:
			for surface in range(mesh_node.mesh.get_surface_count()):
				var mat := mesh_node.get_surface_override_material(surface)
				if mat == null:
					mat = mesh_node.mesh.surface_get_material(surface)
				if mat and mat is StandardMaterial3D:
					var new_mat := mat.duplicate() as StandardMaterial3D
					new_mat.albedo_color = color
					mesh_node.set_surface_override_material(surface, new_mat)

	for child in node.get_children():
		_apply_armor_color(child, color)

func _save_avatar() -> void:
	var nom := name_edit.text.strip_edges()
	if nom.is_empty():
		nom = "Joueur"
	$MainMenuScreen/AvatarCard/AvatarVBox/AvatarNameLabel.text = nom
	$MainMenuScreen/AvatarCard/AvatarVBox/AvatarClassLabel.text = _current_class + "  |  Niveau 1"
	_show(main_menu)

func _select_model(name: String) -> void:
	if not MODEL_SCENES.has(name):
		return
	_selected_model = name
	# Vider le conteneur existant
	for child in char_node.get_children():
		child.queue_free()
	# Instancier le modele GLB
	var scene : PackedScene = MODEL_SCENES[name] as PackedScene
	var inst : Node3D = scene.instantiate() as Node3D
	if inst:
		char_node.add_child(inst)
		inst.transform = Transform3D.IDENTITY
		# Lancer l'animation idle dès que le modèle est ajouté à la scène
		_play_default_animation(inst)
		# Attacher la camera au modele selectionne
		_attach_camera_to_model(inst)
	
	# Assurer que seul le bouton selectionne reste presse
	for btn in $AvatarScreen/AvatarControls/ModelRow.get_children():
		if btn is Button:
			btn.set_pressed(btn.text == name)

func _attach_camera_to_model(model: Node3D) -> void:
	# Positionner la camera pour une vue TPS derriere le modele
	var cam_offset := Vector3(0, 1.2, 2.5)
	avatar_cam.transform.origin = model.to_global(cam_offset)
	avatar_cam.look_at(model.global_transform.origin + Vector3(0, 0.8, 0))

func _play_default_animation(node: Node) -> void:
	var anim_player := node.get_node_or_null("AnimationPlayer")
	if anim_player == null:
		anim_player = node.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if anim_player:
		var animations : Array = anim_player.get_animation_list()
		if animations.size() > 0:
			var animation_name : String = "idle"
			# Vérifier si "idle" existe, sinon prendre la première animation
			if not animations.has("idle"):
				animation_name = animations[0]
			var animation : Animation = anim_player.get_animation(animation_name)
			if animation:
				animation.loop_mode = Animation.LOOP_LINEAR
				anim_player.play(animation_name)

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
	# Passe la configuration a la scene de jeu via un Autoload ou des meta
	if has_node("/root/SessionManager"):
		var sm = get_node("/root/SessionManager")
		sm.solo_config = _solo_config.duplicate()
		sm.selected_model = _selected_model
	print("[Solo] Lancement avec config : ", _solo_config)
	print("[Solo] Modele selectionne : ", _selected_model)
	# Determiner la scene a charger selon la map choisie
	var map_name: String = _solo_config["map"]
	var scene_path: String = MAP_SCENES.get(map_name, "res://scenes/w_1.tscn")
	print("[Solo] Scene cible : ", scene_path)
	get_tree().change_scene_to_file(scene_path)

# ══════════════════════════════════════════════════════════════════════════════
#  Battle Royal — Joindre
# ══════════════════════════════════════════════════════════════════════════════
func _join_br() -> void:
	var code: String  = $BattleRoyalScreen/BRContent/BRLeft/SearchBREdit.text.strip_edges()
	var list: ItemList  = $BattleRoyalScreen/BRContent/BRLeft/BRRoomsList
	var sel: Array   = list.get_selected_items()
	if code.is_empty() and sel.is_empty():
		print("[BR] Selectionnez une room ou entrez un code.")
		return
	var room: String = code if not code.is_empty() else list.get_item_text(sel[0])
	print("[BR] Rejoindre : ", room)
	# ENet/WebSocket — connexion au serveur ici

# ══════════════════════════════════════════════════════════════════════════════
#  Boss Hunt — Joindre
# ══════════════════════════════════════════════════════════════════════════════
func _join_bh() -> void:
	var code: String = $BossHuntScreen/BHContent/BHLeft/SearchBHEdit.text.strip_edges()
	var list: ItemList = $BossHuntScreen/BHContent/BHLeft/BHRoomsList
	var sel: Array = list.get_selected_items()
	if code.is_empty() and sel.is_empty():
		print("[BH] Selectionnez une room ou entrez un code.")
		return
	var room: String = code if not code.is_empty() else list.get_item_text(sel[0])
	print("[BH] Rejoindre : ", room)

# ══════════════════════════════════════════════════════════════════════════════
#  Inviter un joueur
# ══════════════════════════════════════════════════════════════════════════════
func _invite(player_name: String) -> void:
	print("[Invite] Invitation envoyee a : ", player_name)
	# RPC ou WebSocket -> envoyer notification au joueur

# ══════════════════════════════════════════════════════════════════════════════
#  Helper — groupe de boutons toggle (un seul actif a la fois)
# ══════════════════════════════════════════════════════════════════════════════
func _connect_toggle_group(buttons: Array, callback: Callable) -> void:
	for btn in buttons:
		btn.pressed.connect(func():
			for b in buttons:
				b.button_pressed = (b == btn)
			callback.call(btn.text)
		)
