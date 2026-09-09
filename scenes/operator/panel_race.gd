## Contrôle de course — START, STOP, relance, chrono et etat en direct.
##
## Le bouton START est desactive tant que le depart n'est pas autorise, et
## l'infobulle dit POURQUOI. Un bouton grise sans explication est un appel au
## support en pleine soiree.
class_name PanelRace
extends VBoxContainer

## Journal de bord court : les derniers messages, le plus recent en tete.
##
## Le bandeau n'affichait que le dernier. Depuis que le logiciel signale les
## pistes muettes, les pointes suspectes et les trames perdues, l'alerte qui
## compte disparaissait derriere le bavardage suivant — et c'est la plus grave
## qui a le plus de chances d'etre recouverte, puisqu'elle arrive en pleine
## course. Cinq lignes : assez pour ne rien perdre de vue, trop peu pour que ce
## soit une console.
const NOTICE_LINES := 5


var _controller: AppController
var _start: Button
var _stop: Button
var _restart: Button
var _state_label: Label
var _clock_label: Label
var _lanes: Array[Label] = []
var _notice: Label
## Conditions de la session, distinctes des alertes de course : elles survivent
## a l'ardoise propre.
var _startup: Label
var _notices: PackedStringArray = []


func setup(controller: AppController) -> void:
	_controller = controller
	_build()
	_controller.race_state_changed.connect(_on_race_state)
	_controller.link_state_changed.connect(func(_s: int) -> void: refresh())
	_controller.demo_mode_changed.connect(_on_demo_mode_changed)
	_controller.countdown_tick.connect(_on_countdown)
	_controller.progress_updated.connect(_on_progress)
	_controller.notice.connect(_on_notice)
	_controller.race_finished.connect(_on_race_finished)
	_controller.rider_eliminated.connect(_on_rider_eliminated)
	_controller.false_start_detected.connect(_on_false_start)
	refresh()
	# Ce qui a mal tourne au chargement se dit ici, au premier regard — ET Y
	# RESTE. Voir `_startup` : ce n'est pas un evenement, c'est un etat.
	var problems := _controller.startup_problems()
	_startup.visible = not problems.is_empty()
	_startup.text = "\n".join(problems)


func _build() -> void:
	var title := Label.new()
	title.text = "Course"
	title.add_theme_font_size_override("font_size", 20)
	add_child(title)

	var row := HBoxContainer.new()
	add_child(row)
	_start = Button.new()
	_start.text = "START"
	_start.custom_minimum_size = Vector2(140, 48)
	_start.pressed.connect(_on_start)
	row.add_child(_start)

	_stop = Button.new()
	_stop.text = "STOP"
	_stop.custom_minimum_size = Vector2(140, 48)
	_stop.pressed.connect(_on_stop)
	row.add_child(_stop)

	_restart = Button.new()
	_restart.text = "Relancer"
	_restart.custom_minimum_size = Vector2(140, 48)
	_restart.pressed.connect(_on_restart)
	row.add_child(_restart)

	_state_label = Label.new()
	add_child(_state_label)

	_clock_label = Label.new()
	_clock_label.add_theme_font_size_override("font_size", 32)
	add_child(_clock_label)

	for lane: int in range(Protocol.MAX_RIDERS):
		var label := Label.new()
		label.add_theme_font_size_override("font_size", 18)
		add_child(label)
		_lanes.append(label)

	# CE QUI DURE TOUTE LA SOIREE, au-dessus de ce qui passe.
	#
	# Les problemes de demarrage — roster illisible, reglages perdus, courses du
	# jour introuvables — etaient pousses dans le journal, qui se vide a chaque
	# armement. Un operateur qui lance sa premiere course dans la minute
	# perdait donc la SEULE notification lui disant que ses noms de coureurs
	# n'avaient pas ete relus. Il decouvrait « Piste 1, Piste 2 » a l'ecran
	# public, ou dans le CSV le lendemain.
	#
	# Ce n'est pas l'alerte d'une course : c'est une CONDITION de la session,
	# vraie tant que le fichier n'est pas repare. Elle a donc sa place a elle,
	# que l'ardoise propre n'efface pas.
	_startup = Label.new()
	_startup.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_startup.custom_minimum_size.x = 520
	_startup.add_theme_color_override("font_color", Color("#FFB300"))
	_startup.visible = false
	add_child(_startup)

	_notice = Label.new()
	_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notice.custom_minimum_size.x = 520
	add_child(_notice)


func refresh() -> void:
	var can_start := _controller.can_start_race()
	_start.disabled = not can_start
	_start.tooltip_text = (
		"Lancer la course" if can_start else _controller.start_blocked_reason()
	)
	# UNE COURSE TERMINEE N'EST PAS EN COURS. STOP ne doit etre propose que
	# tant qu'il y a quelque chose a arreter : sinon c'est un bouton qui invite
	# au clic et ne fait rien.
	# UNE COURSE TERMINEE NE SE RELANCE PAS NON PLUS. « Relancer » est un STOP
	# suivi d'un START ; sans course en cours son STOP ne fait rien et il ne
	# reste que le START, que le bouton d'a cote fait deja. Deux boutons pour
	# un meme geste, dont l'un porte un nom qui promet autre chose, invitent a
	# croire qu'ils different — la question a d'ailleurs ete posee.
	var running := _controller.race_in_progress()
	_stop.disabled = not running
	_restart.disabled = not running
	_restart.tooltip_text = (
		"Arrêter la course en cours et réarmer la même configuration"
		if running
		else "Rien à relancer : aucune course en cours. START lance la suivante."
	)
	_state_label.text = "État : %s" % RaceEngine.state_label(_controller.engine.state())
	_refresh_lanes()


func start_button() -> Button:
	return _start


func stop_button() -> Button:
	return _stop


func restart_button() -> Button:
	return _restart


## Ce que l'operateur lit sur l'etat de la course.
func state_text() -> String:
	return _state_label.text


## Les conditions de session affichees — pour les tests, qui verifient qu'elles
## survivent au depart d'une course.
func startup_text() -> String:
	return _startup.text if _startup.visible else ""


func notice_text() -> String:
	return _notice.text


func clock_text() -> String:
	return _clock_label.text


func lane_text(lane: int) -> String:
	return _lanes[lane].text


## LES LIGNES SONT CELLES DE LA COURSE, pas du roster vivant. L'operateur qui
## prepare la manche suivante decoche une piste : sa ligne disparaissait alors
## que le moteur la fait courir — distance, vitesse, arrivee, plus rien sous
## ses yeux. Tant que le moteur porte une course — en cours, arrivee, resultat
## affiche —, ce sont ses pistes ; au repos, le roster reprend la main. Noms et
## couleurs restent vivants : le manuel promet la couleur immediate.
func _refresh_lanes() -> void:
	var state := _controller.engine.race_state()
	var race_lanes: Array[int] = []
	if state != null and _controller.engine.state() != RaceEngine.State.IDLE:
		race_lanes = state.config.active_riders
	for lane: int in range(Protocol.MAX_RIDERS):
		var rider := _controller.roster.rider(lane)
		var shown := race_lanes.has(lane) if not race_lanes.is_empty() else rider.active
		if not shown:
			_lanes[lane].text = ""
			_lanes[lane].visible = false
			continue
		_lanes[lane].visible = true
		_lanes[lane].add_theme_color_override("font_color", Color(rider.color))
		if state == null:
			_lanes[lane].text = "P%d %s" % [lane + 1, rider.display_name()]
			continue
		var suffix := ""
		if state.eliminated[lane]:
			suffix = "  ÉLIMINÉ"
		elif state.finished_ms[lane] > 0:
			suffix = "  ARRIVÉ %.2f s" % (state.finished_ms[lane] / 1000.0)
		_lanes[lane].text = (
			"P%d %-14s %7.1f m  %5.1f km/h%s"
			% [
				lane + 1,
				rider.display_name(),
				state.distance_m[lane],
				# La vitesse d'ÉCRAN, lissée : la brute à 100 Hz faisait battre
				# le dixième sous les yeux de l'opérateur.
				state.display_speed_kph[lane],
				suffix,
			]
		)


func _on_start() -> void:
	_controller.start_race()


func _on_stop() -> void:
	_controller.stop_race()


func _on_restart() -> void:
	_controller.restart_race()


func _on_countdown(value: int) -> void:
	_clock_label.text = "DÉPART DANS %d" % value if value > 0 else "PARTEZ"


func _on_progress(state: RaceState) -> void:
	# docs/01 §3 : l'horloge affichee derive de elapsedMs du firmware, jamais de
	# l'horloge du PC.
	_clock_label.text = "%.2f s" % (state.elapsed_ms / 1000.0)
	if state.config.mode == RaceConfig.Mode.PURSUIT:
		# Les plafonds sont visibles a l'operateur aussi — docs/02 §3.
		_clock_label.text += "   (%s)" % RulePursuit.decision_text(state)
	_refresh_lanes()


## Une nouvelle course efface le journal de la precedente : ce qui s'y trouve
## ne concerne plus personne, et une alerte perimee vaut pire que rien.
func _on_race_state(_previous: int, current: int) -> void:
	if current == RaceEngine.State.ARMING:
		_clear_notices()
	refresh()


func _on_notice(text: String) -> void:
	_push_notice(text)


func _push_notice(text: String) -> void:
	if text.is_empty():
		return
	_notices.insert(0, text)
	while _notices.size() > NOTICE_LINES:
		_notices.remove_at(_notices.size() - 1)
	_notice.text = "\n".join(_notices)


## Ardoise propre : une nouvelle course ne traine pas les alertes de l'ancienne.
## A L'ARRET DE LA VITRINE, LE JOURNAL EST RENDU. Ses manches y laissaient
## leurs eliminations et leurs podiums de demonstration — cinq lignes qui
## masquaient les alertes de la derniere vraie course. Le manuel promet
## qu'elles n'ont pas eu lieu ; le journal doit le dire aussi.
func _on_demo_mode_changed(active: bool) -> void:
	if not active:
		_clear_notices()
	refresh()


func _clear_notices() -> void:
	_notices.clear()
	_notice.text = ""


func _on_false_start(rider: int, _policy: int) -> void:
	_push_notice("FAUX DÉPART piste %d" % (rider + 1))


func _on_rider_eliminated(rider: int, rank: int, gap_m: float) -> void:
	_push_notice("Piste %d éliminée (rang %d, écart %.1f m)" % [rider + 1, rank, gap_m])


func _on_race_finished(result: RaceResult) -> void:
	var winner := result.winner()
	_clock_label.text = "%.2f s" % (result.elapsed_ms / 1000.0)
	_push_notice(
		"Terminé — vainqueur piste %d (%s)%s"
		% [
			winner + 1,
			# LES NOMS DU DEPART, portes par le resultat. Le roster courant est
			# deja celui de la course SUIVANTE des que l'operateur le saisit.
			result.display_name(winner),
			"  [INTERROMPUE]" if result.was_stopped() else "",
		]
	)
	refresh()
