## Fenetre operateur — assemble les cinq panneaux.
##
## Construite en code plutot qu'en `.tscn` : c'est un formulaire dense, pilote
## de bout en bout par `Settings` et `Roster`. En scene, chaque champ existerait
## deux fois — une fois dans le `.tscn`, une fois dans le script qui le remplit —
## et il faudrait charger une ressource pour la tester. En code, elle
## s'instancie en headless, ce qui rend le jalon J3 demontrable sans ecran.
##
## La fenetre SPECTACLE, elle, sera une vraie scene : elle releve du travail
## visuel, pas de la saisie (lot 4).
class_name OperatorPanel
extends Control

var controller: AppController

var _roster_panel: PanelRoster
var _mode_panel: PanelMode
var _hardware_panel: PanelHardware
var _race_panel: PanelRace
var _results_panel: PanelResults
var _spectacle_panel: PanelSpectacle
var _root: Node


## `root` est la racine de l'application, celle qui possède les fenêtres. Elle
## est facultative : les outils en ligne de commande montent cette interface
## sans elle, et le panneau spectacle est alors simplement absent.
func setup(app_controller: AppController, root: Node = null) -> void:
	controller = app_controller
	_root = root
	# Le controleur est peut-etre encore vide : l'interface exige qu'il soit
	# pret, elle ne se contente pas de l'esperer.
	controller.initialize()
	_build()


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	# Les colonnes OCCUPENT la fenêtre. Sans ces drapeaux, elles se réduisaient
	# à la largeur de leur contenu et l'interface se tassait en haut à gauche
	# d'un grand fond vide.
	columns.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(columns)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 16)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(left)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 16)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(right)

	_roster_panel = PanelRoster.new()
	left.add_child(_roster_panel)
	_roster_panel.setup(controller)

	_mode_panel = PanelMode.new()
	left.add_child(_mode_panel)
	_mode_panel.setup(controller)

	_hardware_panel = PanelHardware.new()
	left.add_child(_hardware_panel)
	_hardware_panel.setup(controller)

	_race_panel = PanelRace.new()
	right.add_child(_race_panel)
	_race_panel.setup(controller)

	_results_panel = PanelResults.new()
	right.add_child(_results_panel)
	_results_panel.setup(controller)

	# Le pilotage de la fenêtre spectacle s'adresse à la RACINE de
	# l'application, pas au contrôleur de course : c'est elle qui possède les
	# fenêtres. Elle est passée EXPLICITEMENT plutôt que cherchée dans l'arbre :
	# ce panneau est construit avant d'y entrer, et `get_tree()` y journalise
	# une erreur — c'est précisément ce que vérifie
	# `test_l_interface_construite_avant_l_entree_dans_l_arbre_fonctionne`.
	# Sans racine — les outils en ligne de commande — le panneau est simplement
	# absent.
	if _root != null and _root.has_method("open_spectacle"):
		_spectacle_panel = PanelSpectacle.new()
		right.add_child(_spectacle_panel)
		_spectacle_panel.setup(_root, controller)

	# Un changement de roster ou de mode peut rendre le depart possible ou
	# impossible : le bouton START doit suivre immediatement.
	_roster_panel.roster_changed.connect(_on_configuration_changed)
	_mode_panel.mode_changed.connect(_on_configuration_changed)
	_hardware_panel.backend_changed.connect(_on_configuration_changed)

	_hardware_panel.refresh_ports()


func spectacle_panel() -> PanelSpectacle:
	return _spectacle_panel


func roster_panel() -> PanelRoster:
	return _roster_panel


func mode_panel() -> PanelMode:
	return _mode_panel


func hardware_panel() -> PanelHardware:
	return _hardware_panel


func race_panel() -> PanelRace:
	return _race_panel


func results_panel() -> PanelResults:
	return _results_panel


func _on_configuration_changed() -> void:
	_roster_panel.refresh()
	_race_panel.refresh()
	_hardware_panel.refresh()
