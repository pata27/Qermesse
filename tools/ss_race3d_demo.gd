## Mesure et filme la scène 3D — artefact de preuve du jalon J4.
##
##   godot --script tools/ss_race3d_demo.gd -- --mesure [--riders 4] [--qualite moyen]
##   godot --script tools/ss_race3d_demo.gd -- --video <dossier>
##
## **Deux passes, et c'est délibéré.** Lire l'image du viewport pour la filmer
## impose une lecture retour GPU par image, ce qui détruit précisément la
## grandeur qu'on prétend mesurer. La passe `--mesure` ne capture rien : c'est
## elle qui donne le chiffre. La passe `--video` capture, et son framerate n'a
## aucune valeur de preuve.
extends SceneTree

const MEASURE_WARMUP_S := 3.0
const MEASURE_WINDOW_S := 30.0

var _controller: AppController
var _scene: RaceScene
var _mode := "mesure"
var _video_dir := ""
var _riders := 4
var _quality := -1
var _speed := 1.0
var _frame_index := 0
var _last_tick_us := 0


func _initialize() -> void:
	_parse_args()
	# La RÉSOLUTION DE RENDU est forcée à 1080p, indépendamment de la taille de
	# la fenêtre : le gestionnaire de fenêtres bride souvent celle-ci, et une
	# mesure prise à 941x565 ne dirait rien du budget de docs/04 §4.
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	root.content_scale_size = Vector2i(1920, 1080)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	# Aucun plafond de framerate : on mesure ce que la machine peut donner, pas
	# ce que la synchronisation verticale lui autorise.
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_run.call_deferred()


func _parse_args() -> void:
	var args := OS.get_cmdline_user_args()
	var i := 0
	while i < args.size():
		match args[i]:
			"--mesure":
				_mode = "mesure"
			"--video":
				_mode = "video"
				i += 1
				_video_dir = args[i] if i < args.size() else ""
			"--riders":
				i += 1
				_riders = int(args[i]) if i < args.size() else _riders
			"--qualite":
				i += 1
				_quality = RenderQuality.level_from_name(args[i]) if i < args.size() else -1
			"--capture":
				_mode = "capture"
				i += 1
				_video_dir = args[i] if i < args.size() else ""
			"--vitesse":
				i += 1
				_speed = float(args[i]) if i < args.size() else _speed
		i += 1


func _run() -> void:
	_controller = AppController.new()
	_controller.preferences_enabled = false
	root.add_child(_controller)
	_controller.initialize()

	# Roster : `_riders` pistes actives, et un boîtier simulé qui a autant de
	# capteurs câblés — sinon les pistes surnuméraires resteraient à zéro.
	for lane: int in range(Protocol.MAX_RIDERS):
		_controller.roster.set_active(lane, lane < _riders)
	_controller.set_simulator_riders(_riders)
	_controller.set_simulation_speed(_speed)
	_controller.settings.mode = RaceConfig.Mode.DISTANCE
	_controller.settings.distance_m = 500.0

	_scene = RaceScene.new()
	root.add_child(_scene)
	_scene.setup(_controller, _quality)
	# La dégradation automatique est coupée pendant la mesure : on veut le
	# chiffre du profil demandé, pas celui d'un profil qui s'est ajusté.
	_scene.set_auto_degrade(false)

	print("adaptateur     : %s" % RenderQuality.adapter_description())
	print("qualite        : %s" % _scene.quality.level_name())
	print("riders         : %d" % _riders)
	print("fenetre        : %s" % str(DisplayServer.window_get_size()))
	print("rendu          : %s (resolution effective, forcee)" % str(root.content_scale_size))

	await _until(func() -> bool:
		return _controller.link_state() == Protocol.State.IDENTIFIED, 600)
	if not _controller.start_race():
		printerr("ECHEC : %s" % _controller.start_blocked_reason())
		quit(1)
		return

	if _mode == "video":
		await _record()
	elif _mode == "capture":
		await _capture_stills()
	else:
		await _measure()
	quit(0)


func _measure() -> void:
	# Chauffe : compilation des shaders, premiere allocation des tampons. Les
	# inclure dans la mesure donnerait un minimum qui ne veut rien dire.
	var warmup := 0.0
	while warmup < MEASURE_WARMUP_S:
		warmup += await _step()

	_scene.perf.reset()
	var elapsed := 0.0
	while elapsed < MEASURE_WINDOW_S:
		var delta := await _step()
		elapsed += delta
		# Le fps se déduit du temps de CETTE image, pas du compteur lissé du
		# moteur : `Engine.get_frames_per_second()` n'est rafraîchi qu'une fois
		# par seconde, si bien qu'un centile calculé dessus porte sur des
		# valeurs répétées et ne veut rien dire.
		_scene.perf.sample(delta, 1.0 / maxf(delta, 0.000001))

	print("")
	print("=== budget de rendu — docs/04 §4 ===")
	print("cible          : 60 fps stables en 1080p sur GPU integre")
	print(_scene.perf.report())
	print("etat course    : %s, %.1f m" % [
		_controller.engine.state_name(),
		_controller.engine.race_state().distance_m[0] if _controller.engine.race_state() else 0.0,
	])


## Quelques images fixes aux moments cles, pour REGARDER le rendu.
func _capture_stills() -> void:
	DirAccess.make_dir_recursive_absolute(_video_dir)
	var marks := {"depart": 5.0, "lancee": 12.0, "pleine": 22.0}
	var clock := 0.0
	var done: Array[String] = []
	while done.size() < marks.size():
		clock += await _step()
		for label: String in marks:
			if done.has(label) or clock < float(marks[label]):
				continue
			done.append(label)
			await RenderingServer.frame_post_draw
			var image := root.get_texture().get_image()
			var path := _video_dir.path_join("r3d-%d-%s.png" % [_riders, label])
			image.save_png(path)
			print("capture : %s" % path)


func _record() -> void:
	DirAccess.make_dir_recursive_absolute(_video_dir)
	var warmup := 0.0
	while warmup < 2.0:
		warmup += await _step()

	# 30 s a 30 images par seconde : 900 images. La cadence de capture est
	# imposee, elle ne suit pas le framerate reel.
	var target_frames := 900
	var next_capture := 0.0
	var clock := 0.0
	while _frame_index < target_frames:
		clock += await _step()
		if clock >= next_capture:
			next_capture += 1.0 / 30.0
			await RenderingServer.frame_post_draw
			var image := root.get_texture().get_image()
			image.save_png(_video_dir.path_join("frame_%05d.png" % _frame_index))
			_frame_index += 1

	print("")
	print("%d images ecrites dans %s" % [_frame_index, _video_dir])
	print("assembler avec :")
	print("  ffmpeg -y -framerate 30 -i %s/frame_%%05d.png \\" % _video_dir)
	print("    -c:v libx264 -pix_fmt yuv420p -crf 20 %s/j4-course.mp4" % _video_dir)


## Attend une image et rend le temps REELLEMENT ecoule, mesure a l'horloge
## systeme. Deduire le delta du compteur de fps reviendrait a mesurer le fps
## avec le fps.
func _step() -> float:
	await process_frame
	var now := Time.get_ticks_usec()
	var delta := 0.0 if _last_tick_us == 0 else float(now - _last_tick_us) / 1000000.0
	_last_tick_us = now
	return delta


func _until(condition: Callable, max_frames: int) -> void:
	for i: int in range(max_frames):
		if condition.call():
			return
		await process_frame
