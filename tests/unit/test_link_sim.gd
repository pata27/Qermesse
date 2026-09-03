## Tests du simulateur GDScript — docs/03 §5.
##
## Le simulateur doit se comporter comme le firmware, BUGS COMPRIS. Un
## simulateur plus permissif ou plus correct que le materiel laisserait passer
## des bugs jusqu'au terrain, ce qui est exactement l'inverse du but.
extends GutTest

const SIM := preload("res://hardware/link_sim.gd")

var _sim: Node
var _frames: Array[Dictionary] = []
var _states: Array[int] = []


func before_each() -> void:
	_sim = SIM.new()
	_frames.clear()
	_states.clear()
	_sim.frame_received.connect(func(kind: int, payload: Dictionary) -> void:
		_frames.append({"kind": kind, "payload": payload}))
	_sim.state_changed.connect(func(state: int) -> void: _states.append(state))


func after_each() -> void:
	_sim.free()


func _connect_sim() -> void:
	_sim.start()
	_advance(0.5)


## Avance en pas fixes : le comportement ne doit pas dependre du framerate.
func _advance(seconds: float) -> void:
	for i: int in range(int(seconds / 0.02)):
		_sim.advance(0.02)


func _of_kind(kind: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for f: Dictionary in _frames:
		if f["kind"] == kind:
			out.append(f["payload"])
	return out


# --- Constantes physiques ----------------------------------------------------

func test_100_m_avec_un_rouleau_de_114_3_mm_font_278_ticks() -> void:
	# Non-regression v1/v2, docs/01 §7.
	assert_eq(Protocol.ticks_for_metres(100.0), 278)
	assert_almost_eq(Protocol.circumference_mm(), 359.08, 0.01)


func test_les_bornes_d_argument_firmware_de_docs_01() -> void:
	assert_true(Protocol.is_valid_firmware_argument(1))
	assert_true(Protocol.is_valid_firmware_argument(278))
	assert_true(Protocol.is_valid_firmware_argument(32767))
	assert_false(Protocol.is_valid_firmware_argument(0), "zero tick n'a pas de sens")
	assert_false(Protocol.is_valid_firmware_argument(32768), "atoi remplit un int 16 bits")


# --- Handshake ---------------------------------------------------------------

func test_le_depart_n_est_autorise_qu_en_etat_identified() -> void:
	assert_eq(_sim.get_link_state(), Protocol.State.DISCONNECTED)
	assert_false(_sim.can_start_race(), "au repos, START doit etre interdit")

	_sim.start()
	assert_eq(_sim.get_link_state(), Protocol.State.PORT_OPEN)
	assert_false(_sim.can_start_race(), "port ouvert n'est PAS une preuve — la faute de la v1")

	_advance(0.5)
	assert_eq(_sim.get_link_state(), Protocol.State.IDENTIFIED)
	assert_true(_sim.can_start_race())
	assert_eq(_sim.get_firmware_version(), Protocol.FIRMWARE_VERSION)


func test_la_version_est_annoncee_par_une_trame() -> void:
	_connect_sim()
	var versions := _of_kind(Protocol.Frame.VERSION)
	assert_eq(versions.size(), 1)
	assert_eq(versions[0]["text"], "SS_v0.1.7")


# --- Validation des commandes, miroir de docs/01 §2 et §5.5 ------------------

func test_les_commandes_de_la_liste_exhaustive_sont_acceptees() -> void:
	_connect_sim()
	for cmd: String in ["v", "s", "g", "d", "x", "m"]:
		assert_true(_sim.send_command(cmd), "commande %s refusee" % cmd)


func test_toute_commande_hors_liste_est_refusee() -> void:
	_connect_sim()
	for cmd: String in ["", "q", "z", "gg", "G", "S"]:
		assert_false(_sim.send_command(cmd), "commande %s aurait du etre refusee" % cmd)


func test_l_ticks_respecte_les_deux_bornes_du_firmware() -> void:
	_connect_sim()
	assert_true(_sim.send_command("l278"))
	assert_false(_sim.send_command("l0"))
	assert_false(_sim.send_command("l32768"), "au-dela d'un int 16 bits")
	assert_false(_sim.send_command("l12345678"), "8 chiffres debordent charBuff[8]")
	assert_string_contains(_sim.get_last_error(), "7")


func test_toute_duree_qui_ferait_terminer_le_firmware_est_refusee() -> void:
	# docs/01 §5.5 : t600 couperait le flux R: a 10,2 s, en pleine course.
	_connect_sim()
	assert_true(_sim.send_command(Protocol.TIME_COMMAND), "t60 est la valeur sure")
	assert_true(_sim.send_command("t300"))
	assert_false(_sim.send_command("t600"))
	assert_string_contains(_sim.get_last_error(), "10176")
	assert_false(_sim.send_command("t30"), "termine normalement a 30 s, donc coupe R:")


# --- Decompte ----------------------------------------------------------------

func test_le_decompte_emet_cd_3_a_cd_0_a_une_seconde_d_intervalle() -> void:
	_connect_sim()
	_sim.send_command("d")
	_sim.send_command("l278")
	_sim.send_command("g")

	_advance(0.9)
	assert_eq(_of_kind(Protocol.Frame.COUNTDOWN).size(), 0, "rien avant 1000 ms")

	_advance(3.4)
	var values: Array = []
	for p: Dictionary in _of_kind(Protocol.Frame.COUNTDOWN):
		values.append(p["value"])
	assert_eq(values, [3, 2, 1, 0], "le decompte complet dure ~4 s")


# --- LE bug de la v1 ---------------------------------------------------------

func test_course_distance_a_2_capteurs_les_riders_finissent_pas_la_course() -> void:
	# docs/01 §5.1 : le firmware attend les QUATRE pistes materielles. Le
	# simulateur doit reproduire ce blocage, sinon le coeur metier serait teste
	# contre un materiel imaginaire.
	_sim.wired_riders = 2
	_connect_sim()
	_sim.send_command("d")
	_sim.send_command("l278")
	_sim.send_command("g")
	_advance(20.0)

	var finishes := _of_kind(Protocol.Frame.RIDER_FINISH)
	assert_eq(finishes.size(), 2, "seules les deux pistes cablees franchissent la ligne")
	assert_eq(finishes[0]["rider"], 0)
	assert_eq(finishes[1]["rider"], 1)

	var before := _of_kind(Protocol.Frame.PROGRESS).size()
	_advance(2.0)
	assert_gt(_of_kind(Protocol.Frame.PROGRESS).size(), before,
		"le flux R: doit continuer indefiniment")


func test_course_distance_a_4_capteurs_la_course_se_termine() -> void:
	_sim.wired_riders = 4
	_connect_sim()
	_sim.send_command("d")
	_sim.send_command("l278")
	_sim.send_command("g")
	_advance(20.0)

	assert_eq(_of_kind(Protocol.Frame.RIDER_FINISH).size(), 4)
	var before := _of_kind(Protocol.Frame.PROGRESS).size()
	_advance(2.0)
	assert_eq(_of_kind(Protocol.Frame.PROGRESS).size(), before,
		"le flux R: s'arrete quand les 4 pistes ont fini")


# --- Flux de progression -----------------------------------------------------

func test_les_ticks_sont_cumules_et_jamais_decroissants() -> void:
	# docs/01 §3 : R: porte des valeurs ABSOLUES. Ne jamais accumuler de deltas.
	_sim.wired_riders = 2
	_connect_sim()
	_sim.send_command("x")
	_sim.send_command(Protocol.TIME_COMMAND)
	_sim.send_command("g")
	_advance(12.0)

	var frames := _of_kind(Protocol.Frame.PROGRESS)
	assert_gt(frames.size(), 500, "environ 100 trames par seconde")

	var previous := 0
	var previous_ms := -1
	for p: Dictionary in frames:
		var ticks: Array = p["ticks"]
		assert_true(ticks[0] >= previous, "les ticks cumules ne redescendent jamais")
		assert_true(int(p["elapsed_ms"]) > previous_ms, "l'horloge firmware avance")
		assert_eq(ticks[2], 0, "les pistes non cablees restent a zero")
		assert_eq(ticks[3], 0)
		previous = ticks[0]
		previous_ms = int(p["elapsed_ms"])


func test_le_mode_temps_ne_se_termine_jamais_de_lui_meme() -> void:
	# docs/01 §5.5 : avec t60 le firmware ne conclut jamais. C'est le PC qui
	# tranche. Le simulateur doit se taire de la meme facon.
	_sim.wired_riders = 2
	_connect_sim()
	_sim.send_command("x")
	_sim.send_command(Protocol.TIME_COMMAND)
	_sim.send_command("g")
	_advance(70.0)
	assert_eq(_of_kind(Protocol.Frame.RIDER_FINISH).size(), 0)


# --- Injection de pannes -----------------------------------------------------

func test_faux_depart_pendant_le_decompte() -> void:
	_connect_sim()
	_sim.inject_false_start(0)
	_sim.send_command("g")
	_advance(2.0)
	var fs := _of_kind(Protocol.Frame.FALSE_START)
	assert_eq(fs.size(), 1)
	assert_eq(fs[0]["rider"], 0)


func test_tick_fantome_ajoute_un_tick_sans_mouvement() -> void:
	# docs/01 §6.3 : aucun anti-rebond firmware, le filtre est cote PC.
	_sim.wired_riders = 2
	_connect_sim()
	_sim.send_command("x")
	_sim.send_command(Protocol.TIME_COMMAND)
	_sim.send_command("g")
	_advance(6.0)
	var before: Array = _of_kind(Protocol.Frame.PROGRESS).back()["ticks"]
	_sim.inject_phantom_tick(0)
	_advance(0.1)
	var after: Array = _of_kind(Protocol.Frame.PROGRESS).back()["ticks"]
	assert_gt(int(after[0]) - int(before[0]), 0)


func test_trame_corrompue_remonte_en_unknown_sans_rien_casser() -> void:
	_connect_sim()
	_sim.inject_corrupt_frame()
	var unknown := _of_kind(Protocol.Frame.UNKNOWN)
	assert_eq(unknown.size(), 1)
	assert_string_contains(unknown[0]["text"], "\\x01")


func test_un_profil_inconnu_est_refuse_au_lieu_d_etre_ignore() -> void:
	# `set_profile` ignorait un nom inconnu et gardait le precedent. Une faute
	# de frappe dans une commande de preuve — `--profil eparpille` accentue,
	# par exemple — faisait donc tourner `egaux` en silence, et la capture
	# produite montrait tout autre chose que ce qu'elle pretendait montrer.
	assert_true(_sim.set_profile("domination"), "un nom connu est accepte")
	assert_eq(_sim.profile, "domination")

	assert_false(_sim.set_profile("eparpillé"), "un nom inconnu est refuse")
	assert_eq(_sim.profile, "domination", "et l'ancien profil reste en place")

	var noms: Array = _sim.profiles()
	assert_true(noms.has("egaux"), "la liste des profils est disponible pour le dire")
	assert_gt(noms.size(), 5)


func test_les_statistiques_du_simulateur_comptent_vraiment() -> void:
	# Le panneau materiel les affiche : « Trames 0 » pendant qu'une course
	# defile ressemblait a une panne du simulateur.
	_connect_sim()
	_sim.inject_corrupt_frame()
	var stats: Dictionary = _sim.get_stats()
	assert_eq(int(stats["connects"]), 1)
	assert_eq(int(stats["frames_unknown"]), 1)
	assert_eq(int(stats["frames_total"]), _frames.size(), "chaque trame emise est comptee")
	assert_gt(int(stats["frames_total"]), 1, "V: au moins, plus la corrompue")
	_sim.inject_link_loss()
	_sim.inject_link_return()
	stats = _sim.get_stats()
	assert_eq(int(stats["watchdog_trips"]), 1)
	assert_eq(int(stats["connects"]), 2, "reconnexion comptee")


func test_perte_et_retour_du_lien() -> void:
	_connect_sim()
	assert_eq(_sim.get_link_state(), Protocol.State.IDENTIFIED)
	_sim.inject_link_loss()
	assert_eq(_sim.get_link_state(), Protocol.State.LINK_LOST)
	assert_false(_sim.can_start_race(), "lien perdu : START interdit")
	_sim.inject_link_return()
	assert_eq(_sim.get_link_state(), Protocol.State.IDENTIFIED)


# --- Determinisme ------------------------------------------------------------

func test_a_graine_fixee_le_scenario_se_rejoue_a_l_identique() -> void:
	var runs: Array = []
	for run: int in range(2):
		var sim: Node = SIM.new()
		sim.wired_riders = 2
		sim.seed = 7
		var ticks: Array = []
		sim.frame_received.connect(func(kind: int, payload: Dictionary) -> void:
			if kind == Protocol.Frame.PROGRESS:
				ticks.append(payload["ticks"][0]))
		sim.start()
		for i: int in range(600):
			sim.advance(0.02)
		sim.send_command("x")
		sim.send_command(Protocol.TIME_COMMAND)
		sim.send_command("g")
		for i: int in range(600):
			sim.advance(0.02)
		runs.append(ticks)
		sim.free()
	assert_eq(runs[0], runs[1], "meme graine, meme course")
	assert_gt((runs[0] as Array).size(), 100)


# --- Etats atteints ----------------------------------------------------------

func test_chaque_etat_du_lien_est_atteint() -> void:
	# docs/06 §1 : pas d'etat mort.
	_sim.start()
	_advance(0.5)
	_sim.inject_link_loss()
	_sim.inject_link_return()
	_sim.stop()
	assert_has(_states, Protocol.State.PORT_OPEN)
	assert_has(_states, Protocol.State.IDENTIFIED)
	assert_has(_states, Protocol.State.LINK_LOST)
	assert_has(_states, Protocol.State.DISCONNECTED)
