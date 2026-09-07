## La vitrine — `scenes/attract_mode.gd`.
##
## Une borne d'arcade ne reste jamais noire entre deux joueurs. Ici c'est le
## même besoin : entre deux manches, le projecteur affichait un podium figé ou
## rien, et la file se dissout.
##
## Ce que ces tests protègent n'est PAS le spectacle — il se juge à l'image —
## mais les deux promesses qui l'entourent : la vitrine ne laisse aucune trace,
## et elle rend tout ce qu'elle emprunte. Une démonstration qui polluerait
## « Courses du jour » ou qui changerait la distance de course sous les pieds de
## l'opérateur serait pire que pas de vitrine du tout.
extends GutTest

const TEST_ROOT := "user://test_vitrine"

var _main: Node
var _logs: String
var _races: String


func before_each() -> void:
	_logs = ProjectSettings.globalize_path(TEST_ROOT).path_join("logs")
	_races = ProjectSettings.globalize_path(TEST_ROOT).path_join("races")
	_wipe()
	_main = (load("res://scenes/main.gd") as GDScript).new()
	_main.preferences_enabled = false
	_main.recorder_logs_dir = _logs
	_main.recorder_races_dir = _races
	add_child_autofree(_main)
	# La suite ne peut pas attendre trois manches reelles : en production la
	# vitrine tourne a vitesse normale, c'est tout son interet.
	_main.attract.speed_scale = 8.0


func after_each() -> void:
	if _main != null and _main.attract != null and _main.attract.is_running():
		_main.attract.stop()
	if _main != null and _main.spectacle != null:
		_main.spectacle.queue_free()
		_main.spectacle = null
	_wipe()


func _wipe() -> void:
	for dir: String in [_logs, _races]:
		if DirAccess.dir_exists_absolute(dir):
			for name: String in DirAccess.get_files_at(dir):
				DirAccess.remove_absolute(dir.path_join(name))


func _files(dir: String) -> int:
	return 0 if not DirAccess.dir_exists_absolute(dir) else DirAccess.get_files_at(dir).size()


func _await_identified() -> bool:
	for i: int in range(600):
		await wait_physics_frames(1)
		if _main.controller.link_state() == Protocol.State.IDENTIFIED:
			return true
	return false


func test_la_vitrine_ne_laisse_aucune_trace() -> void:
	# LA PROMESSE CENTRALE. Ces courses n'ont pas eu lieu : les laisser atterrir
	# dans le journal du jour, dans le dossier des courses ou dans « Courses du
	# jour » rendrait la soiree de l'operateur illisible — et un doute sur ce
	# qui a REELLEMENT ete couru est un doute sur tout le fichier.
	var controller: AppController = _main.controller
	assert_true(await _await_identified(), "le simulateur repond")
	_main.open_spectacle()
	assert_true(_main.attract.start(), "la vitrine demarre")

	var finished: Array[RaceResult] = []
	controller.race_finished.connect(func(r: RaceResult) -> void: finished.append(r))
	for i: int in range(1800):
		await wait_physics_frames(1)
		if not finished.is_empty():
			break
	assert_false(finished.is_empty(), "au moins une manche est allee au bout")

	# L'arret abandonne la manche en cours : c'est l'AUTRE chemin d'ecriture,
	# celui qui ecrivait un resultat partiel. Il compte autant.
	_main.attract.stop()
	await wait_physics_frames(2)

	assert_eq(controller.history().size(), 0, "rien dans Courses du jour")
	assert_eq(_files(_logs), 0, "aucun journal ecrit")
	assert_eq(_files(_races), 0, "aucun fichier de course ecrit")
	assert_false(controller.demo_mode, "et le mode demo est bien retombe")


func test_la_vitrine_rend_tout_ce_qu_elle_emprunte() -> void:
	# Un reglage oublie, c'est une configuration silencieusement changee sous
	# les pieds de l'operateur, qui lancera sa vraie course suivante sur la
	# distance de la demonstration.
	var controller: AppController = _main.controller
	assert_true(await _await_identified())
	controller.settings.mode = RaceConfig.Mode.TIME
	controller.settings.distance_m = 777.0
	controller.settings.gap_m = 33.0
	for lane: int in range(Protocol.MAX_RIDERS):
		controller.roster.set_active(lane, lane == 0)
	controller.set_simulator_profile("deux-groupes")
	controller.set_simulator_riders(3)

	_main.open_spectacle()
	assert_true(_main.attract.start())
	for i: int in range(900):
		await wait_physics_frames(1)
	# Pendant la vitrine, les reglages ONT bouge : c'est ce qui fait le
	# spectacle. La promesse porte sur l'apres.
	_main.attract.stop()
	await wait_physics_frames(2)

	assert_eq(controller.settings.mode, RaceConfig.Mode.TIME, "le mode est rendu")
	assert_almost_eq(controller.settings.distance_m, 777.0, 0.01, "la distance aussi")
	assert_almost_eq(controller.settings.gap_m, 33.0, 0.01, "et l'ecart de poursuite")
	assert_eq(controller.roster.active_lanes(), [0] as Array[int], "les pistes actives aussi")
	assert_eq(controller.simulator_profile(), "deux-groupes", "le profil du simulateur")
	assert_eq(controller.simulator_riders(), 3, "et ses capteurs cables")
	assert_almost_eq(controller.simulation_speed(), 1.0, 0.01, "et la vitesse du simulateur")


func test_la_vitrine_ne_coupe_jamais_une_vraie_course() -> void:
	# On n'interrompt pas des gens qui pedalent pour lancer une demonstration.
	var controller: AppController = _main.controller
	assert_true(await _await_identified())
	controller.settings.distance_m = 400.0
	assert_true(controller.start_race(), "une vraie course part")
	for i: int in range(900):
		await wait_physics_frames(1)
		if controller.engine.state() == RaceEngine.State.RUNNING:
			break
	assert_eq(controller.engine.state(), RaceEngine.State.RUNNING, "elle court")

	var notices: Array[String] = []
	controller.notice.connect(func(text: String) -> void: notices.append(text))
	assert_false(_main.attract.start(), "la vitrine refuse de demarrer")
	assert_false(_main.attract.is_running(), "et ne demarre effectivement pas")
	assert_eq(controller.engine.state(), RaceEngine.State.RUNNING, "la course continue")
	var said := false
	for text: String in notices:
		if text.contains("mode démo"):
			said = true
	assert_true(said, "et le refus est dit a l'operateur")
	controller.engine.abort("fin du test")


func test_la_vitrine_enchaine_des_scenarios_differents() -> void:
	# Une vitrine qui rejouerait la meme course en boucle ne donne pas envie
	# d'essayer : c'est la VARIETE qui montre ce que le logiciel sait faire.
	var controller: AppController = _main.controller
	assert_true(await _await_identified())
	_main.open_spectacle()
	assert_true(_main.attract.start())
	var modes: Array[int] = []
	for i: int in range(3600):
		await wait_physics_frames(1)
		var mode: int = controller.settings.mode
		if modes.is_empty() or modes[modes.size() - 1] != mode:
			modes.append(mode)
		if modes.size() >= 3:
			break
	assert_gte(modes.size(), 3, "au moins trois manches enchainees")
	# Les trois modes du logiciel passent : c'est le catalogue, en images.
	var distinct: Array[int] = []
	for mode: int in modes:
		if not distinct.has(mode):
			distinct.append(mode)
	assert_gte(distinct.size(), 2, "et pas toujours le meme mode")


func test_la_vitrine_tourne_a_vitesse_reelle() -> void:
	# Elle a d'abord accelere le simulateur trois fois, sur l'idee qu'une
	# demonstration n'a pas a durer ce que dure une course. C'etait une faute :
	# des coureurs qui pedalent en accelere se lisent comme un defaut, pas comme
	# un resume. Le reglage par defaut est donc le temps reel, et l'ecart n'est
	# qu'une couture de test.
	var fresh := AttractMode.new()
	autofree(fresh)
	assert_almost_eq(
		fresh.speed_scale, 1.0, 0.001, "la vitrine ne fait pas courir en accelere"
	)


func test_la_camera_monte_quand_elle_tourne() -> void:
	# La main courante est a 4,9 m de l'axe et les gradins sont juste derriere :
	# une orbite a hauteur constante finit DEDANS, et la camera filme a travers
	# le decor. Rien dans une capture ne dit qu'une orbite est trop plate — on
	# le voit une fois qu'on est dans les gradins.
	var offset := Vector3(2.0, 1.75, -4.0)
	var flat := CameraRig.cine_offset(offset, 0.0, 1.0)
	# Horloge a zero : le sinus de l'angle vaut zero, la camera est a sa place.
	assert_almost_eq(flat.x, offset.x, 0.001, "sans angle, pas de deport")

	# Un quart de periode plus loin, l'angle est maximal.
	var quarter := PI / 2.0 / 0.21
	var swung := CameraRig.cine_offset(offset, quarter, 1.0)
	assert_gt(absf(swung.x - offset.x), 0.5, "la camera a bien tourne")
	assert_gt(swung.y, flat.y + 1.5, "et elle a pris de la hauteur en tournant")

	# Sans vitrine, rien ne bouge : la camera de course n'a pas d'idees.
	assert_eq(CameraRig.cine_offset(offset, quarter, 0.0), offset, "en course, immobile")


func test_l_orbite_garde_sa_distance_au_sujet() -> void:
	# C'est une ORBITE, pas un deport : la distance au coureur ne change pas,
	# donc le cadrage tient. Un deport lateral aurait fait grossir et retrecir
	# le coureur au fil du mouvement.
	var offset := Vector3(2.0, 1.75, -4.0)
	var flat := Vector2(offset.x, offset.z).length()
	for step: int in range(8):
		var moved := CameraRig.cine_offset(offset, float(step) * 2.0, 1.0)
		assert_almost_eq(
			Vector2(moved.x, moved.z).length(), flat, 0.001,
			"image %d : meme distance au sujet, vue d'en haut" % step
		)


func test_fermer_pendant_la_vitrine_ne_grave_pas_ses_reglages() -> void:
	# LE CHEMIN QUE LA RESTITUTION NE COUVRAIT PAS. La vitrine rend tout ce
	# qu'elle emprunte a l'ARRET — mais la fermeture du logiciel sauvegarde sans
	# rien demander a personne, et elle passait donc avant. Fermer pendant la
	# demonstration remplacait silencieusement la configuration de la soiree par
	# le dernier scenario : distance, pistes actives, et jusqu'au choix du
	# backend, si bien qu'au lancement suivant le vrai boitier n'etait plus
	# utilise.
	var controller: AppController = _main.controller
	var dir := ProjectSettings.globalize_path(TEST_ROOT)
	DirAccess.make_dir_recursive_absolute(dir)
	controller.preferences_enabled = true
	controller.settings_path = dir.path_join("settings.json")
	controller.roster_path = dir.path_join("roster.json")

	assert_true(await _await_identified())
	controller.settings.mode = RaceConfig.Mode.TIME
	controller.settings.distance_m = 777.0
	controller.apply_backend(false)
	for lane: int in range(Protocol.MAX_RIDERS):
		controller.roster.set_active(lane, lane == 0)
	assert_true(controller.save_preferences(), "les reglages de l'operateur sont poses")

	_main.open_spectacle()
	assert_true(_main.attract.start())
	for i: int in range(600):
		await wait_physics_frames(1)
	assert_ne(controller.settings.distance_m, 777.0, "la vitrine a bien pris la main")

	# Fermeture, vitrine en cours.
	_main.notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	await wait_physics_frames(2)

	var written := Settings.new()
	written.load_from(controller.settings_path)
	var roster := Roster.new()
	roster.load_from(controller.roster_path)
	assert_eq(written.mode, RaceConfig.Mode.TIME, "le mode de l'operateur est sur le disque")
	assert_almost_eq(written.distance_m, 777.0, 0.01, "sa distance aussi")
	assert_false(written.use_simulator, "et son choix de materiel, surtout")
	assert_eq(roster.active_lanes(), [0] as Array[int], "ses pistes actives aussi")
	DirAccess.remove_absolute(controller.settings_path)
	DirAccess.remove_absolute(controller.roster_path)


func test_la_sauvegarde_se_refuse_d_elle_meme_pendant_la_vitrine() -> void:
	# La garde est posee sur `save_preferences` et non chez ses appelants : il y
	# en a trois, et c'est le troisieme — la fermeture — qui a montre qu'une
	# garde par appelant est une garde a oublier.
	var controller: AppController = _main.controller
	var dir := ProjectSettings.globalize_path(TEST_ROOT)
	DirAccess.make_dir_recursive_absolute(dir)
	controller.preferences_enabled = true
	controller.settings_path = dir.path_join("refus.json")
	controller.demo_mode = true
	assert_true(controller.save_preferences(), "elle rend vrai : ce n'est pas un echec")
	assert_false(
		FileAccess.file_exists(controller.settings_path),
		"mais rien n'est ecrit tant que la vitrine tourne"
	)
	controller.demo_mode = false
	assert_true(controller.save_preferences())
	assert_true(FileAccess.file_exists(controller.settings_path), "et tout revient apres")
	DirAccess.remove_absolute(controller.settings_path)


func test_le_bouton_demo_dit_l_etat_de_la_vitrine_pas_le_dernier_clic() -> void:
	# Mesure a la sonde : vitrine lancee, le bouton disait encore « Mode démo » ;
	# vitrine arretee par le code — fermeture du logiciel —, il disait encore
	# « Arrêter ». Le texte ne suivait que les changements de fenetre.
	_main.open_spectacle()
	var button: Button = _main.operator.spectacle_panel().demo_button()
	assert_string_contains(button.text, "Mode démo")
	assert_true(_main.attract.start())
	assert_string_contains(button.text, "Arrêter", "la vitrine tourne, le bouton le dit")
	_main.attract.stop()
	assert_string_contains(button.text, "Mode démo", "elle est arretee, le bouton le dit")


func test_le_bouton_demo_se_grise_des_qu_une_vraie_course_part() -> void:
	# Le manuel : « grisé pendant une course ». Il ne l'etait qu'au prochain
	# changement de fenetre ; entre-temps il repondait par un refus au journal.
	_main.open_spectacle()
	var button: Button = _main.operator.spectacle_panel().demo_button()
	assert_true(await _await_identified())
	assert_false(button.disabled, "au repos, fenetre ouverte : disponible")
	assert_true(_main.controller.start_race())
	assert_true(button.disabled, "grise des le depart")
	assert_string_contains(button.tooltip_text, "pendant une course")
	_main.controller.stop_race()
	assert_false(button.disabled, "rendu des la fin")


func test_fermer_la_fenetre_spectacle_arrete_la_vitrine() -> void:
	# « Il n'y aurait rien à montrer » vaut aussi pour une vitrine deja lancee :
	# elle continuait a enchainer des manches pour personne, reglages
	# empruntes, jusqu'a ce que quelqu'un pense a cliquer.
	_main.open_spectacle()
	var distance: float = _main.controller.settings.distance_m
	assert_true(_main.attract.start())
	assert_ne(_main.controller.settings.distance_m, distance, "la vitrine a emprunte la distance")
	_main.close_spectacle()
	assert_false(_main.attract.is_running(), "plus de fenetre, plus de vitrine")
	assert_false(_main.controller.demo_mode, "et le mode demo est rendu")
	assert_eq(_main.controller.settings.distance_m, distance, "les reglages aussi")
	var button: Button = _main.operator.spectacle_panel().demo_button()
	assert_string_contains(button.text, "Mode démo")
	assert_true(button.disabled, "et grise : il n'y a rien a montrer")
