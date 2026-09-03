## Racine de l'application — docs/03 §2, « routeur ».
##
## Instancie le contrôleur, la fenêtre opérateur et, à la demande, la fenêtre
## spectacle. Ne contient AUCUNE logique de course : il route, c'est tout.
extends Node

## Émis à chaque changement d'état de la fenêtre spectacle, pour que le panneau
## opérateur reflète la réalité plutôt que ce qu'il a demandé.
signal spectacle_changed()

var controller: AppController
var operator: OperatorPanel
var spectacle: SpectacleWindow
var audio: RaceAudio
## La vitrine — ce que l'écran montre quand personne ne pédale. Elle vit ICI et
## non dans le panneau : elle pilote le contrôleur et la scène, c'est-à-dire
## exactement les deux choses que ce routeur tient déjà.
var attract: AttractMode


## Coutures, posees AVANT l'entree dans l'arbre : `_ready` construit le
## controleur, qui lit aussitot les reglages et le roster de l'utilisateur. Un
## test qui les laisserait actives lirait l'etat reel de la machine — et son
## resultat dependrait de la derniere soiree de l'operateur.
var preferences_enabled := true
var recorder_logs_dir := ""
var recorder_races_dir := ""


func _ready() -> void:
	controller = AppController.new()
	controller.name = "AppController"
	controller.preferences_enabled = preferences_enabled
	controller.recorder_logs_dir = recorder_logs_dir
	controller.recorder_races_dir = recorder_races_dir
	add_child(controller)

	operator = OperatorPanel.new()
	operator.name = "OperatorPanel"
	add_child(operator)
	audio = RaceAudio.new()
	audio.name = "RaceAudio"
	add_child(audio)
	audio.setup(controller)

	attract = AttractMode.new()
	attract.name = "AttractMode"
	add_child(attract)
	attract.setup(controller, self)

	operator.setup(controller, self)

	var window := get_window()
	window.title = "SilverSprint v3 — operateur"
	window.min_size = Vector2i(1100, 760)
	# TAILLE EXPLICITE. Sans elle, le gestionnaire de fenêtres ouvre souvent la
	# fenêtre au maximum, et l'interface — qui tient en deux colonnes — flottait
	# dans un immense fond vide. Une fenêtre d'outil doit avoir la taille de son
	# contenu ; l'opérateur l'agrandit s'il le veut.
	window.size = Vector2i(1320, 900)
	# Sous Wayland le compositeur place les fenêtres ; demander une position
	# ne sert à rien et peut la faire changer d'écran. Voir `SpectacleWindow`.
	if not SpectacleWindow.compositor_places_windows():
		var area := DisplayServer.screen_get_usable_rect(window.current_screen)
		window.position = area.position + (area.size - window.size) / 2

	# La fenêtre spectacle est rouverte telle qu'elle a été laissée : sur son
	# écran, en plein écran ou non. Un opérateur qui a réglé sa projection la
	# veille ne doit pas avoir à recommencer (docs/02 §5).
	if not controller.settings.single_window_mode:
		open_spectacle()


## Ouvre — ou ramène au premier plan — la fenêtre spectacle.
func open_spectacle() -> void:
	if spectacle == null:
		spectacle = SpectacleWindow.new()
		spectacle.name = "SpectacleWindow"
		add_child(spectacle)
		spectacle.setup(
			controller,
			controller.settings.show_window_screen,
			controller.settings.spectacle_fullscreen,
			controller.settings.render_quality
		)
		spectacle.closed_by_user.connect(_on_spectacle_closed)
	else:
		spectacle.move_to(
			controller.settings.show_window_screen, spectacle.is_fullscreen()
		)
		spectacle.show()
	controller.settings.single_window_mode = false
	spectacle_changed.emit()


## Ferme la fenêtre spectacle. La course, elle, continue : l'affichage public
## n'est pas la course.
func close_spectacle() -> void:
	if spectacle != null:
		spectacle.hide()
	controller.settings.single_window_mode = true
	spectacle_changed.emit()


func spectacle_visible() -> bool:
	return spectacle != null and spectacle.visible


## Déplace la fenêtre spectacle sur un écran et mémorise le choix.
func set_spectacle_screen(screen: int) -> void:
	controller.settings.show_window_screen = screen
	if spectacle != null and spectacle.visible:
		spectacle.move_to(screen, spectacle.is_fullscreen())
	spectacle_changed.emit()


func set_spectacle_fullscreen(enabled: bool) -> void:
	# Memorise MEME si la fenetre n'est pas ouverte : c'est un reglage de
	# projection, pris la veille, pas l'etat d'une fenetre.
	controller.settings.spectacle_fullscreen = enabled
	if spectacle != null and spectacle.visible:
		spectacle.set_fullscreen(enabled)
	spectacle_changed.emit()


func spectacle_fullscreen() -> bool:
	# Sans fenetre ouverte, c'est le reglage qui fait foi — sinon la case du
	# panneau afficherait « non » avant d'ouvrir une fenetre plein ecran.
	if spectacle == null or not spectacle.visible:
		return controller.settings.spectacle_fullscreen
	return spectacle.is_fullscreen()


func _on_spectacle_closed() -> void:
	controller.settings.single_window_mode = true
	spectacle_changed.emit()


func _notification(what: int) -> void:
	# Une course en cours est arretee — le boitier aussi —, puis les noms des
	# riders et les reglages sont persistes : la v1 les perdait a chaque
	# lancement (docs/02 §5).
	if what == NOTIFICATION_WM_CLOSE_REQUEST and controller != null:
		controller.shutdown()
