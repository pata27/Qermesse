## Contrôle de course — START, STOP, relance, chrono et etat en direct.
##
## Le bouton START est desactive tant que le depart n'est pas autorise, et
## l'infobulle dit POURQUOI. Un bouton grise sans explication est un appel au
## support en pleine soiree.
class_name PanelRace
extends VBoxContainer

var _controller: AppController
var _start: Button
var _stop: Button
var _restart: Button
var _state_label: Label
var _clock_label: Label
var _lanes: Array[Label] = []
var _notice: Label


func setup(controller: AppController) -> void:
	_controller = controller
	_build()
	_controller.race_state_changed.connect(func(_p: int, _c: int) -> void: refresh())
	_controller.link_state_changed.connect(func(_s: int) -> void: refresh())
	_controller.countdown_tick.connect(_on_countdown)
	_controller.progress_updated.connect(_on_progress)
	_controller.notice.connect(_on_notice)
	_controller.race_finished.connect(_on_race_finished)
	_controller.rider_eliminated.connect(_on_rider_eliminated)
	_controller.false_start_detected.connect(_on_false_start)
	refresh()
	# Ce qui a mal tourne au chargement se dit ici, au premier regard.
	if not _controller.startup_problems().is_empty():
		_notice.text = "\n".join(_controller.startup_problems())


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
	var running := _controller.engine.state() != RaceEngine.State.IDLE
	_stop.disabled = not running
	_restart.disabled = not running and not can_start
	_state_label.text = "Etat : %s" % _controller.engine.state_name()
	_refresh_lanes()


func start_button() -> Button:
	return _start


func stop_button() -> Button:
	return _stop


func restart_button() -> Button:
	return _restart


func notice_text() -> String:
	return _notice.text


func clock_text() -> String:
	return _clock_label.text


func lane_text(lane: int) -> String:
	return _lanes[lane].text


func _refresh_lanes() -> void:
	var state := _controller.engine.race_state()
	for lane: int in range(Protocol.MAX_RIDERS):
		var rider := _controller.roster.rider(lane)
		if not rider.active:
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
			suffix = "  ELIMINE"
		elif state.finished_ms[lane] > 0:
			suffix = "  ARRIVE %.2f s" % (state.finished_ms[lane] / 1000.0)
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
	_clock_label.text = "DEPART DANS %d" % value if value > 0 else "PARTEZ"


func _on_progress(state: RaceState) -> void:
	# docs/01 §3 : l'horloge affichee derive de elapsedMs du firmware, jamais de
	# l'horloge du PC.
	_clock_label.text = "%.2f s" % (state.elapsed_ms / 1000.0)
	if state.config.mode == RaceConfig.Mode.PURSUIT:
		# Les plafonds sont visibles a l'operateur aussi — docs/02 §3.
		_clock_label.text += "   (%s)" % RulePursuit.decision_text(state)
	_refresh_lanes()


func _on_notice(text: String) -> void:
	_notice.text = text


func _on_false_start(rider: int, _policy: int) -> void:
	_notice.text = "FAUX DEPART piste %d" % (rider + 1)


func _on_rider_eliminated(rider: int, rank: int, gap_m: float) -> void:
	_notice.text = "Piste %d eliminee (rang %d, ecart %.1f m)" % [rider + 1, rank, gap_m]


func _on_race_finished(result: RaceResult) -> void:
	var winner := result.winner()
	_clock_label.text = "%.2f s" % (result.elapsed_ms / 1000.0)
	_notice.text = (
		"Termine — vainqueur piste %d (%s)%s"
		% [
			winner + 1,
			# LES NOMS DU DEPART, portes par le resultat. Le roster courant est
			# deja celui de la course SUIVANTE des que l'operateur le saisit.
			Roster.shorten(result.rider_name(winner)),
			"  [INTERROMPUE]" if result.interrupted else "",
		]
	)
	refresh()
