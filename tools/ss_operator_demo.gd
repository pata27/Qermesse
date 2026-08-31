## Deroule une course complete dans la vraie fenetre operateur, en n'agissant
## que sur les widgets — c'est l'artefact de preuve du jalon J3.
##
##   godot --script tools/ss_operator_demo.gd -- [--capture <dossier>] [--vitesse <x>]
##
## Sans `--capture`, tourne en headless et se contente d'imprimer le CSV.
## Avec, ouvre une fenetre, enregistre des captures aux moments cles, puis
## imprime le CSV.
extends SceneTree

const STEPS := ["configure", "countdown", "course", "resultats"]

var _controller: AppController
var _panel: OperatorPanel
var _capture_dir := ""
var _speed := 4.0
var _shots: Array[String] = []
var _finished: Array[RaceResult] = []


func _initialize() -> void:
	_parse_args()

	_controller = AppController.new()
	_controller.preferences_enabled = false
	root.add_child(_controller)

	_panel = OperatorPanel.new()
	root.add_child(_panel)
	_panel.setup(_controller)
	_controller.set_simulation_speed(_speed)
	_controller.race_finished.connect(func(r: RaceResult) -> void: _finished.append(r))

	if not _capture_dir.is_empty():
		DirAccess.make_dir_recursive_absolute(_capture_dir)
		# La fenetre est dimensionnee via le DisplayServer : `root.set_size`
		# seul ne s'applique pas avant la premiere image, et les captures
		# sortaient tronquees a droite.
		DisplayServer.window_set_size(Vector2i(1320, 900))
		root.set_size(Vector2i(1320, 900))

	_run.call_deferred()


func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		match args[i]:
			"--capture":
				i += 1
				_capture_dir = args[i] if i < args.size() else ""
			"--vitesse":
				i += 1
				_speed = float(args[i]) if i < args.size() else _speed
		i += 1


func _run() -> void:
	# Le gestionnaire de fenetres applique la taille de facon asynchrone : sans
	# cette attente, les premieres captures sortent plus etroites que les
	# dernieres. On attend que la taille se stabilise avant de photographier.
	if not _capture_dir.is_empty():
		var target := Vector2i(1320, 900)
		await _until(func() -> bool:
			return DisplayServer.window_get_size().x >= target.x - 8, 300)
		await _wait_frames(10)
		print("fenetre        : %s" % str(DisplayServer.window_get_size()))

	await _until(func() -> bool:
		return _controller.link_state() == Protocol.State.IDENTIFIED, 400)
	print("lien           : %s, firmware %s"
		% [Protocol.state_name(_controller.link_state()), _controller.firmware_version()])

	# --- configuration, uniquement par les widgets --------------------------
	var roster_panel := _panel.roster_panel()
	_type(roster_panel.name_field(0), "Alice")
	_type(roster_panel.name_field(1), "Bob")

	var mode_panel := _panel.mode_panel()
	var selector := mode_panel.mode_selector()
	var index := selector.get_item_index(RaceConfig.Mode.DISTANCE)
	selector.select(index)
	selector.item_selected.emit(index)
	mode_panel.distance_field().value = 100.0

	var race_panel := _panel.race_panel()
	race_panel.refresh()
	print("depart autorise : %s" % ("oui" if not race_panel.start_button().disabled
		else "NON — " + _controller.start_blocked_reason()))
	await _shoot("configure")

	# --- un clic ------------------------------------------------------------
	race_panel.start_button().pressed.emit()
	await _until(func() -> bool:
		return _controller.engine.state() == RaceEngine.State.COUNTDOWN, 400)
	await _shoot("countdown")

	await _until(func() -> bool:
		return _controller.engine.state() == RaceEngine.State.RUNNING, 800)
	await _wait_frames(int(120 / maxf(1.0, _speed)) + 30)
	print("en course      : %s" % race_panel.clock_text())
	await _shoot("course")

	await _until(func() -> bool: return not _finished.is_empty(), 4000)
	if _finished.is_empty():
		printerr("ECHEC : la course ne s'est pas terminee")
		quit(1)
		return
	await _wait_frames(5)
	await _shoot("resultats")

	_report(_finished[0])
	quit(0)


func _report(result: RaceResult) -> void:
	print("")
	print("=== resultat ===")
	print("mode %s, fin : %s%s" % [result.mode, result.end_reason_name(),
		"  [INTERROMPUE]" if result.interrupted else ""])
	for rider: int in result.ranking:
		print("  rang %d  piste %d  %-8s %7.1f m  %6.2f s  moy %5.1f km/h  max %5.1f km/h"
			% [result.rank_of(rider), rider + 1,
			_controller.roster.rider(rider).display_name(),
			result.distance_m[rider], result.finished_ms[rider] / 1000.0,
			result.avg_kph[rider], result.max_kph[rider]])

	print("")
	print("=== CSV : %s ===" % _controller.recorder.csv_path())
	var file := FileAccess.open(_controller.recorder.csv_path(), FileAccess.READ)
	if file != null:
		print(file.get_as_text().strip_edges())
		file.close()
	if not _shots.is_empty():
		print("")
		print("=== captures ===")
		for path: String in _shots:
			print("  %s" % path)


func _type(field: LineEdit, text: String) -> void:
	field.text = text
	field.text_changed.emit(text)


func _wait_frames(count: int) -> void:
	for i: int in range(count):
		await process_frame


func _until(condition: Callable, max_frames: int) -> void:
	for i: int in range(max_frames):
		if condition.call():
			return
		await process_frame


func _shoot(name: String) -> void:
	if _capture_dir.is_empty():
		return
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var path := _capture_dir.path_join("j3-%s.png" % name)
	if image.save_png(path) == OK:
		_shots.append(path)
