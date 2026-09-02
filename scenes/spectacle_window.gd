## Fenêtre spectacle — la seconde fenêtre, celle que le public voit (docs/03 §6).
##
## **Pourquoi une vraie fenêtre et non un panneau.** L'opérateur travaille sur
## son écran pendant que le public regarde le sien : ce sont deux surfaces
## indépendantes, avec leur résolution, leur plein écran et leur mode de
## rafraîchissement. Un `Window` de Godot EST un `Viewport` — la scène 3D y vit
## entièrement, et la fenêtre opérateur n'en paie rien.
##
## **Monde 3D séparé.** `own_world_3d` est indispensable : sans lui, la fenêtre
## spectacle partagerait le monde de la fenêtre opérateur, qui se mettrait alors
## à afficher le vélodrome derrière ses panneaux.
##
## **Mode dégradé mono-écran.** Sur une machine à un seul écran — le cas d'une
## répétition, ou d'un vidéoprojecteur pas encore branché — la fenêtre s'ouvre
## en fenêtré sur l'écran principal. Rien n'est refusé : l'opérateur doit
## pouvoir tout préparer sans matériel de projection.
class_name SpectacleWindow
extends Window

signal closed_by_user()

## Taille par défaut en mode fenêtré. Volontairement 16:9 : c'est le format de
## tout vidéoprojecteur, et cadrer autre chose donnerait une fausse idée du
## rendu final.
const WINDOWED_SIZE := Vector2i(1280, 720)

var scene: RaceScene

var _controller: AppController


func _init() -> void:
	title = "SilverSprint — spectacle"
	# Monde 3D distinct de celui de la fenêtre opérateur : voir l'en-tête.
	own_world_3d = true
	size = WINDOWED_SIZE
	min_size = Vector2i(640, 360)
	# La résolution de rendu suit la fenêtre, mais la composition est pensée
	# pour du 1080p : `CONTENT_SCALE_MODE_VIEWPORT` conserve les proportions de
	# l'habillage quel que soit le projecteur.
	content_scale_size = Vector2i(1920, 1080)
	content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	close_requested.connect(_on_close_requested)


## Monte la scène 3D et place la fenêtre. `screen` négatif signifie « choisis
## pour moi » : l'écran secondaire s'il existe, l'écran principal sinon.
func setup(controller: AppController, screen: int, fullscreen: bool, quality: int = -1) -> void:
	_controller = controller
	scene = RaceScene.new()
	scene.name = "RaceScene"
	add_child(scene)
	scene.setup(controller, quality)
	move_to(screen, fullscreen)


## Déplace la fenêtre sur un écran, en plein écran ou non.
##
## L'ordre compte : Godot ignore un changement d'écran demandé alors que la
## fenêtre est déjà en plein écran. On repasse donc en fenêtré, on déménage,
## puis on remet le plein écran.
func move_to(screen: int, fullscreen: bool) -> void:
	if mode == Window.MODE_FULLSCREEN:
		mode = Window.MODE_WINDOWED
	# SOUS WAYLAND, ON NE CHOISIT PAS D'ÉCRAN. C'est le compositeur qui place
	# les fenêtres ; tout ce que l'application demande ici — écran, position —
	# il le suit ou l'ignore à sa guise. Vérifié sous Hyprland : une règle du
	# compositeur envoyait la fenêtre sur eDP-1, et l'application la ramenait
	# aussitôt sur « l'écran 2 » de son énumération X11, en plein écran par-
	# dessus le marché. Se battre est perdu d'avance ; on s'abstient, et
	# docs/DEPANNAGE.md donne la règle à écrire côté compositeur.
	if not compositor_places_windows():
		var target := resolve_screen(screen)
		current_screen = target
		if not fullscreen:
			size = WINDOWED_SIZE
			# Centrée sur son écran : une fenêtre qui s'ouvre à cheval sur deux
			# écrans est le premier réflexe qu'on nous reproche.
			var area := DisplayServer.screen_get_usable_rect(target)
			position = area.position + (area.size - size) / 2
	else:
		# SOUS WAYLAND, PAS DE PLEIN ÉCRAN DEMANDÉ PAR L'APPLICATION NON PLUS.
		#
		# Une requête plein écran X11 emporte la géométrie de l'écran que Godot
		# croit être le sien — hérité de la fenêtre principale, donc de l'écran
		# où était la SOURIS au lancement — et le compositeur honore cette
		# géométrie de préférence à sa propre règle de placement. Résultat
		# vérifié : la fenêtre spectacle suivait la souris, pas la règle.
		#
		# Le plein écran est donc laissé au compositeur, comme l'écran : la
		# règle documentée dans docs/DEPANNAGE.md fait les deux, sans course
		# possible. Sans règle, le raccourci du compositeur reste disponible.
		size = WINDOWED_SIZE
		mode = Window.MODE_WINDOWED
		return
	mode = Window.MODE_FULLSCREEN if fullscreen else Window.MODE_WINDOWED


## Vrai quand un compositeur Wayland décide du placement des fenêtres. Godot
## tourne alors le plus souvent en XWayland, et `DisplayServer.get_name()`
## répond « X11 » : c'est la session qu'il faut regarder, pas le pilote.
static func compositor_places_windows() -> bool:
	return (
		OS.get_environment("XDG_SESSION_TYPE") == "wayland"
		or not OS.get_environment("WAYLAND_DISPLAY").is_empty()
	)


## Écran effectivement utilisable pour la valeur demandée.
##
## `-1` ou une valeur hors bornes veut dire « choisis » : le second écran s'il
## existe, faute de quoi le principal. C'est le mode dégradé mono-écran, et il
## ne se signale pas par un refus mais par une fenêtre qui s'ouvre quand même.
static func resolve_screen(wanted: int) -> int:
	var count := DisplayServer.get_screen_count()
	if wanted >= 0 and wanted < count:
		return wanted
	return 1 if count > 1 else 0


func is_fullscreen() -> bool:
	return mode == Window.MODE_FULLSCREEN


func set_fullscreen(enabled: bool) -> void:
	move_to(current_screen, enabled)


func _on_close_requested() -> void:
	# Fermer la fenêtre spectacle ne ferme JAMAIS l'application : l'opérateur
	# doit pouvoir la rouvrir, et une course en cours continue.
	hide()
	closed_by_user.emit()
