## Mesure et filme la scène 3D — artefact de preuve du jalon J4.
##
##   godot --script tools/ss_race3d_demo.gd -- --mesure [--riders 4] [--qualite moyen]
##   godot --script tools/ss_race3d_demo.gd -- --video <dossier>
##   godot --script tools/ss_race3d_demo.gd -- --capture <dossier> --courses 2
##   godot --script tools/ss_race3d_demo.gd -- --capture <dossier> --noms Alice,Bob
##   godot --script tools/ss_race3d_demo.gd -- --capture <dossier> --faux-depart 1
##   godot --script tools/ss_race3d_demo.gd -- --capture <dossier> --faux-depart 1 \
##       --politique relance
##   godot --script tools/ss_race3d_demo.gd -- --capture <dossier> --perte-lien 4
##
## Codes de sortie : 0 fait, 1 depart refuse, 2 scene impossible a charger,
## 3 delai maximal depasse (`--delai N`, 300 s par defaut), 4 fond trop clair
## (`docs/04` §4), 5 budget de rendu non tenu (idem). L'outil ne pend jamais :
## une course qui ne se termine pas est un bug a signaler, pas a subir. Et il ne
## sort jamais a zero en annoncant le contraire : une exigence chiffree qu'on
## imprime sans la faire echouer n'est qu'une observation.
##
## **Deux passes, et c'est délibéré.** Lire l'image du viewport pour la filmer
## impose une lecture retour GPU par image, ce qui détruit précisément la
## grandeur qu'on prétend mesurer. La passe `--mesure` ne capture rien : c'est
## elle qui donne le chiffre. La passe `--video` capture, et son framerate n'a
## aucune valeur de preuve.
extends SceneTree

## Plafond de luminance du fond — docs/04 §4, « léger se mesure ».
##
## LE VERDICT NE VAUT QUE SUR LA SCENE DE REFERENCE, et c'est une correction de
## ma propre garde. Le plafond avait ete cale sur une course de 250 m, ou la
## bande observee ne voit guere que le ciel : 35,9. Sur 100 m la camera cadre
## plus pres, la bande attrape les gradins eclaires, et la MEME scene saine
## monte a 48, puis 55 selon le niveau. La garde accusait donc un rendu
## irreprochable — le plus sur moyen de la faire ignorer.
##
## Deplacer la bande ne sauve rien : plus haut, les memes scenes donnent 46 a 65
## contre 81 pour le defaut recherche. C'est le cadrage qui domine, pas la
## brume. Une luminance absolue n'est comparable qu'a cadrage identique.
##
## Le verdict est donc rendu sur la CONFIGURATION DE CALIBRAGE et sur elle
## seule ; ailleurs, le chiffre est imprime sans conclusion. Il attrape ce pour
## quoi il existe : l'albedo blanche portait ce meme cadrage a 62.
const BACKGROUND_LUMINANCE_MAX := 45.0
## Course sur laquelle le plafond a ete mesure — deux coureurs, 250 m, `egaux`.
const LUMINANCE_REFERENCE_M := 250.0
const LUMINANCE_REFERENCE_RIDERS := 2
const MEASURE_WARMUP_S := 3.0
const MEASURE_WINDOW_S := 30.0

var _controller: AppController
var _scene: RaceScene
var _mode := "mesure"
var _video_dir := ""
var _riders := 4
## Une capture trop claire ne fait pas échouer la capture en cours — on veut
## toutes les images — mais elle fait sortir en erreur à la fin.
var _luminance_failed := false
## Le budget de rendu de `docs/04` §4 n'a pas ete tenu — sortie en erreur.
var _budget_failed := false
## Piste sur laquelle injecter un faux depart, ou -1. Voir `--faux-depart`.
var _false_start_lane := -1
## Instant de course, en secondes, ou couper le lien simule. Negatif : jamais.
var _link_loss_at_s := -1.0
## Politique de faux depart appliquee a la course — voir `--politique`.
var _policy := RaceConfig.FalseStartPolicy.WARN
var _quality := -1
var _speed := 1.0
## Dossier de donnees des outils de preuve — JAMAIS celui de l'operateur.
##
## Les demos font des courses completes : elles enregistrent donc un CSV et un
## JSON par course, comme le logiciel. Ecrivant par defaut dans les donnees de
## l'utilisateur, elles ont rempli sa liste « Courses du jour » de dizaines de
## courses qu'il n'a jamais faites — et la CI en ajoute a chaque execution.
## `--donnees <dossier>` vise ailleurs, y compris les vraies donnees si on veut
## les inspecter.
var _data_dir := ProjectSettings.globalize_path("user://demo")
var _render_factor := 1.0
var _deadline_s := 300.0
## `--courses N` : N courses d'affilee, capturees chacune. Une seule course ne
## voit jamais ce qu'un deuxieme depart doit remettre a zero.
var _races := 1
var _names := PackedStringArray()
var _race_index := 1
var _deadline_us := 0
var _frame_index := 0
var _race_mode := "distance"
var _profile := "egaux"
## Relevé image par image, pour distinguer un coût permanent d'un à-coup.
var _frames_path := OS.get_environment("SS_FRAMES")
## Résolution de rendu. Réglable pour distinguer un coût de REMPLISSAGE d'un
## coût de géométrie : si le temps suit le nombre de pixels, c'est le premier.
var _render_size := Vector2i(1920, 1080)
## Durée de la fenêtre de mesure. Réglable pour pouvoir RÉPÉTER une mesure :
## sur une machine qui n'est pas au repos, un relevé unique ne distingue pas un
## effet coûteux d'une charge de fond.
var _window_s := MEASURE_WINDOW_S
## Distance de course. Réglable pour amener la ligne d'arrivée dans la fenêtre
## de capture : à 500 m elle tombe une quarantaine de secondes après le départ.
var _distance_m := 0.0
## Durée du mode temps, pour la même raison que la distance : amener la fin
## dans la fenêtre de capture.
var _duration_s := 0.0
## Longueur de la vidéo, en images à 30 i/s. 900 = les trente secondes exigées
## par J4 ; une preuve par mode peut être plus courte.
var _video_frames := 900
var _last_tick_us := 0


func _initialize() -> void:
	_parse_args()
	# ÉCHEC IMMÉDIAT si la scène ne se charge pas. Une erreur de parse dans
	# `race_scene.gd` laissait l'outil tourner à vide jusqu'au timeout externe.
	var scene_script := load("res://scenes/race3d/race_scene.gd") as GDScript
	if scene_script == null or not scene_script.can_instantiate():
		printerr("ECHEC : scenes/race3d/race_scene.gd ne se charge pas — voir les erreurs ci-dessus")
		quit(2)
		return
	# DÉLAI MAXIMAL. Un outil de preuve ne pend jamais : passé `--delai`
	# secondes de temps mur, il s'arrête avec un code non nul, quoi qu'il
	# attende — une course qui ne se termine pas est exactement le genre de
	# bug qu'il doit signaler, pas subir.
	_deadline_us = Time.get_ticks_usec() + int(_deadline_s * 1000000.0)
	# La RÉSOLUTION DE RENDU est forcée à 1080p, indépendamment de la taille de
	# la fenêtre : le gestionnaire de fenêtres bride souvent celle-ci, et une
	# mesure prise à 941x565 ne dirait rien du budget de docs/04 §4.
	# En mode capture, la fenêtre est minuscule mais le rendu reste en 1080p :
	# l'image enregistrée est en pleine résolution et la fenêtre n'accapare pas
	# l'écran. En mode mesure, la fenêtre fait la taille demandée — c'est le
	# coût de pixels qu'on veut mesurer, pas celui d'une vignette.
	if _mode == "capture":
		DisplayServer.window_set_size(Vector2i(384, 216))
		DisplayServer.window_set_position(Vector2i(12, 12))
	else:
		DisplayServer.window_set_size(_render_size)
	root.content_scale_size = _render_size
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	# Aucun plafond de framerate : on mesure ce que la machine peut donner, pas
	# ce que la synchronisation verticale lui autorise.
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	_run.call_deferred()


## Arrete l'outil sur une valeur qu'il ne comprend pas, en proposant les
## bonnes. Le silence produirait une preuve qui ne montre pas ce qu'elle dit.
func _bad_argument(option: String, given: String, valid: Array) -> void:
	printerr(
		"ECHEC : %s inconnu « %s ». Disponibles : %s" % [option, given, ", ".join(valid)]
	)
	quit(1)


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
				if i < args.size():
					_quality = RenderQuality.level_from_name(args[i])
					if _quality < 0:
						_bad_argument("qualite", args[i], RenderQuality.level_names())
			"--capture":
				_mode = "capture"
				i += 1
				_video_dir = args[i] if i < args.size() else ""
			"--mode-course":
				i += 1
				_race_mode = args[i] if i < args.size() else _race_mode
			"--profil":
				i += 1
				_profile = args[i] if i < args.size() else _profile
			"--perte-lien":
				# Coupe le lien SIMULE a cet instant de course, en secondes, et
				# capture le bandeau. `docs/RECETTE.md` §6 — « le test qui
				# compte » — exige une capture de ce bandeau, et rien ne
				# permettait de la produire sans debrancher un vrai cable.
				i += 1
				_link_loss_at_s = float(args[i]) if i < args.size() else -1.0
			"--politique":
				# Politique de faux depart, pour produire les trois bandeaux
				# publics que `docs/02` §4 decrit : avertissement, penalite,
				# relance. Seul le premier avait jamais ete capture.
				i += 1
				if i < args.size():
					_policy = RaceConfig.policy_from_name(args[i], _policy)
			"--faux-depart":
				# Injecte un faux depart sur cette piste PENDANT le decompte —
				# le firmware ne le signale qu'a ce moment (docs/01 §2). Sert a
				# produire la preuve de `docs/RECETTE.md` §7, qui demande de
				# constater le bandeau : personne ne l'avait jamais capture.
				i += 1
				_false_start_lane = int(args[i]) if i < args.size() else -1
			"--images":
				i += 1
				_video_frames = int(args[i]) if i < args.size() else _video_frames
			"--duree":
				i += 1
				_duration_s = float(args[i]) if i < args.size() else _duration_s
			"--distance":
				i += 1
				_distance_m = float(args[i]) if i < args.size() else _distance_m
			"--fenetre":
				i += 1
				_window_s = float(args[i]) if i < args.size() else _window_s
			"--rendu":
				i += 1
				var wh: PackedStringArray = args[i].split("x") if i < args.size() \
					else PackedStringArray()
				if wh.size() == 2:
					_render_size = Vector2i(int(wh[0]), int(wh[1]))
			"--vitesse":
				i += 1
				_speed = float(args[i]) if i < args.size() else _speed
			"--donnees":
				i += 1
				if i < args.size():
					_data_dir = args[i]
			"--noms":
				# Noms des coureurs, separes par des virgules. Sert a REGARDER
				# ce que fait l'habillage d'un nom long, que les tests bornent
				# en pixels mais ne dessinent pas.
				i += 1
				_names = (args[i] if i < args.size() else "").split(",", false)
			"--courses":
				i += 1
				_races = maxi(1, int(args[i])) if i < args.size() else _races
			"--delai":
				i += 1
				_deadline_s = float(args[i]) if i < args.size() else _deadline_s
			"--facteur-3d":
				# Ce que la fenêtre spectacle applique d'elle-même sur un
				# projecteur plus petit que 1080p (docs/04) : 0.667 pour du 720p.
				i += 1
				_render_factor = float(args[i]) if i < args.size() else _render_factor
			_:
				# UNE OPTION INCONNUE ARRETE L'OUTIL. Ignoree, une faute de
				# frappe — `--rendus` pour `--rendu` — laissait la valeur par
				# defaut et la mesure portait sur autre chose que ce que la
				# commande annonçait.
				printerr("ECHEC : option inconnue « %s »" % args[i])
				quit(1)
				return
		i += 1


func _run() -> void:
	_controller = AppController.new()
	_controller.preferences_enabled = false
	_controller.recorder_logs_dir = _data_dir.path_join("logs")
	_controller.recorder_races_dir = _data_dir.path_join("races")
	root.add_child(_controller)
	_controller.initialize()

	# Roster : `_riders` pistes actives, et un boîtier simulé qui a autant de
	# capteurs câblés — sinon les pistes surnuméraires resteraient à zéro.
	for lane: int in range(Protocol.MAX_RIDERS):
		_controller.roster.set_active(lane, lane < _riders)
		if lane < _names.size():
			_controller.roster.rider(lane).name = _names[lane]
	_controller.set_simulator_riders(_riders)
	# UN PROFIL INCONNU ARRETE L'OUTIL. L'ignorer ferait tourner `egaux` en
	# silence, et la capture produite montrerait autre chose que son nom.
	if not _controller.set_simulator_profile(_profile):
		printerr(
			"ECHEC : profil inconnu « %s ». Disponibles : %s"
			% [_profile, ", ".join(_controller.simulator_profiles())]
		)
		quit(1)
		return
	_controller.set_simulation_speed(_speed)
	if not ["distance", "temps", "poursuite"].has(_race_mode):
		_bad_argument("mode-course", _race_mode, ["distance", "temps", "poursuite"])
		return
	match _race_mode:
		"temps":
			_controller.settings.mode = RaceConfig.Mode.TIME
			_controller.settings.duration_s = _duration_s if _duration_s > 0.0 else 60.0
		"poursuite":
			_controller.settings.mode = RaceConfig.Mode.PURSUIT
			_controller.settings.gap_m = 50.0
			# `--duree` borne la poursuite : c'est le plafond de durée, et la
			# jauge « décision dans » devient visible sur une capture courte.
			if _duration_s > 0.0:
				_controller.settings.pursuit_time_cap_s = maxf(10.0, _duration_s)
		"distance":
			_controller.settings.mode = RaceConfig.Mode.DISTANCE
			_controller.settings.distance_m = _distance_m if _distance_m > 0.0 else 500.0
	_controller.settings.false_start_policy = _policy

	_scene = RaceScene.new()
	root.add_child(_scene)
	_scene.setup(_controller, _quality)
	if _render_factor < 1.0:
		_scene.set_render_factor(_render_factor)
		print("facteur 3d     : %.3f" % _render_factor)
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
		# Les courses suivantes partent du bouton START, comme en soiree : la
		# precedente est acquittee, le podium reste jusqu'au decompte.
		while _race_index < _races:
			_race_index += 1
			if not _controller.start_race():
				printerr("ECHEC course %d : %s" % [_race_index, _controller.start_blocked_reason()])
				quit(1)
				return
			await _capture_stills()
	else:
		await _measure()
	# Une preuve qui montre un fond laiteux n'est pas une preuve : on sort en
	# erreur, images gardées, pour que l'écart se voie AVANT d'être publié.
	if _luminance_failed:
		printerr("fond trop clair : la brume efface les gradins (docs/04 §4)")
		quit(4)
		return
	if _budget_failed:
		printerr("budget de rendu NON TENU sur cette machine (docs/04 §4)")
		quit(5)
		return
	quit(0)


func _measure() -> void:
	# Chauffe : compilation des shaders, premiere allocation des tampons. Les
	# inclure dans la mesure donnerait un minimum qui ne veut rien dire.
	var warmup := 0.0
	while warmup < MEASURE_WARMUP_S:
		warmup += await _step()

	_scene.perf.reset()
	var trace := PackedStringArray()
	var elapsed := 0.0
	while elapsed < _window_s:
		var delta := await _step()
		elapsed += delta
		# Le fps se déduit du temps de CETTE image, pas du compteur lissé du
		# moteur : `Engine.get_frames_per_second()` n'est rafraîchi qu'une fois
		# par seconde, si bien qu'un centile calculé dessus porte sur des
		# valeurs répétées et ne veut rien dire.
		_scene.perf.sample(delta, 1.0 / maxf(delta, 0.000001))
		if not _frames_path.is_empty():
			trace.append("%.6f %d %d %d" % [
				delta,
				RenderingServer.get_rendering_info(
					RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME
				),
				RenderingServer.get_rendering_info(
					RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME
				),
				_scene.split_pane_count(),
			])

	if not _frames_path.is_empty():
		var file := FileAccess.open(_frames_path, FileAccess.WRITE)
		if file != null:
			file.store_string("# delta appels_de_rendu primitives volets\n")
			file.store_string("\n".join(trace))
			file.close()
			print("trace image par image : %s" % _frames_path)

	print("")
	print("=== recensement des instances ===")
	print(_scene.census())
	print("")
	print("=== budget de rendu — docs/04 §4 ===")
	print("cible          : 60 fps stables en 1080p sur GPU integre")
	print(_scene.perf.report())
	# UN BUDGET NON TENU FAIT SORTIR EN ERREUR. L'outil imprimait « budget NON
	# TENU » et sortait a zero : une mesure lancee depuis un script annoncait
	# donc un succes en disant l'inverse, exactement le defaut deja corrige sur
	# le controle de luminance. Le budget de `docs/04` §4 est une exigence, pas
	# une observation.
	if not _scene.perf.budget_met():
		_budget_failed = true
	print("etat course    : %s, %.1f m" % [
		_controller.engine.state_name(),
		_controller.engine.race_state().distance_m[0] if _controller.engine.race_state() else 0.0,
	])


## Quelques images fixes aux moments cles, pour REGARDER le rendu.
##
## `partez` est le signal de depart lui-meme, plein ecran. Il manquait : `depart`
## est pris trois secondes plus tard, quand le chrono a deja remplace le mot.
## L'instant que les coureurs attendent n'avait jamais ete vu en image.
func _capture_stills() -> void:
	DirAccess.make_dir_recursive_absolute(_video_dir)
	var marks := {"depart": 3.0, "lancee": 9.0, "pleine": 18.0}
	var done: Array[String] = []
	# `has_run` est indispensable : avant le départ l'état vaut ARMING, et sortir
	# sur « pas EN_COURSE » quittait la boucle à la première image.
	# Le décompte se capture AVANT le départ : c'est un état à part entière.
	# UNE COURSE ANNULEE N'EST PAS UNE COURSE QUI PEND. Avec la politique
	# RELANCE, un faux depart arrete la course : l'outil attendait alors une
	# arrivee qui ne viendrait jamais et sortait au bout de cinq minutes en
	# code 3, « delai depasse ». Il sait desormais que la course a ete
	# interrompue, le dit, et s'arrete la — apres avoir pris ses captures, qui
	# sont precisement ce qu'on lui demandait.
	var aborted: Array[String] = []
	_controller.race_aborted.connect(func(note: String) -> void: aborted.append(note))

	var shown_countdown := false
	while not shown_countdown:
		await _step()
		if _controller.engine.state() == RaceEngine.State.COUNTDOWN:
			if _false_start_lane >= 0:
				_controller.simulate_false_start(_false_start_lane)
				# Le bandeau arrive avec la trame `FS:`, pas au meme instant.
				for _wait: int in range(20):
					await _step()
				await _shoot("faux-depart")
			await _shoot("decompte")
			shown_countdown = true
		elif _controller.engine.state() == RaceEngine.State.RUNNING:
			shown_countdown = true

	# L'INSTANT DU DEPART, qui n'etait capture par aucune preuve. `depart` est
	# pris trois secondes plus tard, quand le chrono a deja remplace le mot :
	# le « PARTEZ ! » plein ecran, celui que les coureurs attendent et que les
	# LED du boitier doivent accompagner, n'avait jamais ete vu en image.
	#
	# On l'attrape sur la transition vers EN COURSE — c'est `CD:0` qui la
	# provoque (docs/01 §2), donc l'image suivante porte encore le mot.
	while _controller.engine.state() == RaceEngine.State.COUNTDOWN:
		await _step()
	if _controller.engine.state() == RaceEngine.State.RUNNING:
		await _shoot("partez")

	var has_run := false
	var racing := true
	# On reste dans la boucle tant que la course COURT, même une fois tous les
	# repères horaires pris : les captures d'après-ligne doivent attendre la fin
	# réelle. En mode distance la ligne tombait avant le dernier repère et le
	# défaut ne se voyait pas ; en mode temps, à 60 s, elles étaient prises en
	# pleine course et le « podium » montrait deux coureurs à mi-parcours.
	while racing:
		await _step()
		var state := _controller.engine.race_state()
		var race_s: float = 0.0 if state == null else float(state.elapsed_ms) / 1000.0
		var running := _controller.engine.state() == RaceEngine.State.RUNNING
		has_run = has_run or running
		racing = (running or not has_run) and aborted.is_empty()
		# COUPURE DU LIEN A CHAUD, puis capture du bandeau. Le PC accorde trois
		# secondes de grace (docs/01 §6.2) : on coupe, on laisse le bandeau
		# monter, on photographie, et on rebranche pour que la course reprenne —
		# c'est exactement le scenario que `docs/RECETTE.md` §6 fait constater.
		if running and _link_loss_at_s >= 0.0 and race_s >= _link_loss_at_s:
			_link_loss_at_s = -1.0
			_controller.simulate_link_loss()
			for _wait: int in range(30):
				await _step()
			await _shoot("lien-perdu")
			_controller.simulate_link_return()
		# Le premier franchissement alors que la course continue : c'est le cas
		# ou un coureur arrive bien avant les autres, et il faut le regarder.
		if running and state != null and not done.has("premier"):
			for lane: int in state.config.active_riders:
				if state.finished_ms[lane] > 0:
					done.append("premier")
					await _shoot("premier")
					marks["premier"] = 0.0
					break
		for label: String in marks:
			if done.has(label) or race_s < float(marks[label]):
				continue
			done.append(label)
			await _shoot(label)

	# PAS D'APRÈS-LIGNE SANS LIGNE. Une course annulée pendant le décompte —
	# politique RELANCE — n'a ni arrivée, ni podium : les quatre captures
	# d'après-ligne montraient alors une scène vide sous des noms qui promettent
	# un résultat. Une preuve trompeuse est pire qu'une preuve absente.
	if not has_run:
		print("course annulée avant le départ : %s" % (
			aborted[0] if not aborted.is_empty() else "motif inconnu"
		))
		print("pas de captures d'après-ligne — il n'y a pas eu de course.")
		return

	# CAPTURES D'APRÈS-LIGNE, déclenchées par la fin de course et non par le
	# chrono : sur une course courte, la ligne tombe avant le premier repère
	# horaire, et c'est justement le moment qu'on veut regarder.
	var since := 0.0
	var after := {"arrivee": 0.9, "celebration": 3.0, "regroupe": 4.6, "podium": 6.0}
	var shot: Array[String] = []
	while shot.size() < after.size() and since < 10.0:
		since += await _step()
		if OS.get_environment("SS_DIAG") == "1":
			var st := _controller.engine.race_state()
			print("apres-ligne t=%.2f etat=%s state=%s finis=%s" % [
				since, _controller.engine.state_name(),
				"null" if st == null else "ok",
				"?" if st == null else str(st.finished_ms)])
		for label: String in after:
			if shot.has(label) or since < float(after[label]):
				continue
			shot.append(label)
			await _shoot(label)


## Enregistre une image sous son libellé.
func _shoot(label: String) -> void:
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	var suffix := "" if _races == 1 else "-course%d" % _race_index
	var path := _video_dir.path_join("r3d-%d-%s%s.png" % [_riders, label, suffix])
	image.save_png(path)
	print("capture : %s" % path)
	if label == "lancee":
		_check_background_luminance(image)


## Vérifie que la brume ne laisse pas le fond partir au gris — docs/04 §4.
##
## Le volumétrique a déjà fait cette faute : à albédo blanche, il diffusait les
## projecteurs de salle dans tout le volume et la luminance du fond passait de
## 33 à 75. Aucun test unitaire ne pouvait le voir — c'est une propriété de
## l'IMAGE, pas du code. Elle se mesure donc ici, sur la capture, à l'endroit
## où la spec la borne : la bande haute, gradins compris, sous la bannière.
func _check_background_luminance(image: Image) -> void:
	var width := image.get_width()
	var height := image.get_height()
	var top := int(height * 0.10)
	var bottom := int(height * 0.35)
	if width <= 0 or bottom <= top:
		return
	var total := 0.0
	var count := 0
	# Un pixel sur quatre en x et en y : seize fois moins de lectures pour une
	# moyenne qui ne bouge pas de plus d'un dixième.
	for y: int in range(top, bottom, 4):
		for x: int in range(0, width, 4):
			var c := image.get_pixel(x, y)
			total += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			count += 1
	var luminance := 255.0 * total / float(maxi(count, 1))
	var calibrated := (
		_riders == LUMINANCE_REFERENCE_RIDERS
		and is_equal_approx(_distance_m, LUMINANCE_REFERENCE_M)
	)
	if not calibrated:
		print(
			"fond : luminance %.1f — pas de verdict, le plafond est mesure sur"
			% luminance
			+ " %d coureurs a %.0f m (docs/04 §4)"
			% [LUMINANCE_REFERENCE_RIDERS, LUMINANCE_REFERENCE_M]
		)
		return
	var verdict := "CONFORME" if luminance <= BACKGROUND_LUMINANCE_MAX else "TROP CLAIR"
	print(
		"fond : luminance %.1f / %d — %s (docs/04 §4)"
		% [luminance, BACKGROUND_LUMINANCE_MAX, verdict]
	)
	if luminance > BACKGROUND_LUMINANCE_MAX:
		_luminance_failed = true


func _record() -> void:
	DirAccess.make_dir_recursive_absolute(_video_dir)
	var warmup := 0.0
	while warmup < 2.0:
		warmup += await _step()

	# 30 s a 30 images par seconde : 900 images. La cadence de capture est
	# imposee, elle ne suit pas le framerate reel.
	var target_frames := _video_frames
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
	_check_deadline()
	var now := Time.get_ticks_usec()
	var delta := 0.0 if _last_tick_us == 0 else float(now - _last_tick_us) / 1000000.0
	_last_tick_us = now
	return delta


func _until(condition: Callable, max_frames: int) -> void:
	for i: int in range(max_frames):
		if condition.call():
			return
		await process_frame
		_check_deadline()


func _check_deadline() -> void:
	if _deadline_us > 0 and Time.get_ticks_usec() > _deadline_us:
		var state := "?" if _controller == null else str(_controller.engine.state())
		printerr(
			"DELAI DEPASSE : %.0f s de temps mur, etat moteur %s — l'outil s'arrete"
			% [_deadline_s, state]
		)
		quit(3)
