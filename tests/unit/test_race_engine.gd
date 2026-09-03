## Tests du coeur metier — jalon J2 de docs/05.
##
## Tout tourne en headless, sans scene, sans port serie, sans rendu. Le moteur
## n'emet pas de commandes : il emet `command_requested`, ce qui permet de
## verifier ce qu'il AURAIT envoye au firmware sans qu'aucun materiel existe.
extends GutTest

var _engine: RaceEngine
var _commands: Array[String] = []
var _states: Array[int] = []
var _finishes: Array[Dictionary] = []
var _eliminations: Array[Dictionary] = []
var _rejections: Array[String] = []
var _result: RaceResult = null
var _now_ms: int = 0


func before_each() -> void:
	_engine = RaceEngine.new()
	_commands.clear()
	_states.clear()
	_finishes.clear()
	_eliminations.clear()
	_rejections.clear()
	_result = null
	_now_ms = 0
	_engine.command_requested.connect(func(c: String) -> void: _commands.append(c))
	_engine.state_changed.connect(func(_p: int, c: int) -> void: _states.append(c))
	_engine.rider_finished.connect(func(r: int, ms: int, rank: int) -> void:
		_finishes.append({"rider": r, "ms": ms, "rank": rank}))
	_engine.rider_eliminated.connect(func(r: int, rank: int, gap: float) -> void:
		_eliminations.append({"rider": r, "rank": rank, "gap": gap}))
	_engine.tick_rejected.connect(func(_r: int, d: String) -> void: _rejections.append(d))
	_engine.race_finished.connect(func(res: RaceResult) -> void: _result = res)


func _config(mode: RaceConfig.Mode, riders: Array[int]) -> RaceConfig:
	var config := RaceConfig.new()
	config.mode = mode
	config.active_riders = riders
	return config


## Deroule le decompte firmware jusqu'au depart.
func _countdown() -> void:
	for value: int in [3, 2, 1, 0]:
		_now_ms += 1000
		_engine.tick(_now_ms)
		_engine.on_countdown(value)


## Injecte des trames `R:` a 100 Hz pour des vitesses constantes, en km/h.
## Rend le nombre de trames emises.
## `late_speeds` remplace `speeds` a partir de `switch_s` : un rider qui
## change d'allure en cours de course, SANS repartir de zero — appeler deux
## fois cette fonction faisait reculer les compteurs, et le filtre rejetait
## tout le second appel en silence.
func _run_race(
	seconds: float, speeds: Array, from_ms: int = 0, late_speeds: Array = [], switch_s: float = 0.0
) -> int:
	var physics := Physics.new()
	var distances := [0.0, 0.0, 0.0, 0.0]
	var frames := 0
	var ms := from_ms
	while ms < from_ms + int(seconds * 1000.0):
		ms += 10
		var ticks: Array = []
		var current: Array = speeds
		if not late_speeds.is_empty() and ms - from_ms > int(switch_s * 1000.0):
			current = late_speeds
		for rider: int in range(Protocol.MAX_RIDERS):
			var kph: float = current[rider] if rider < current.size() else 0.0
			distances[rider] += kph * Physics.KPH_TO_MM_PER_MS * 10.0
			ticks.append(int(floor(distances[rider] / physics.circumference_mm)))
		_engine.on_progress(ticks, ms)
		frames += 1
		if _engine.state() != RaceEngine.State.RUNNING:
			break
	return frames


# =============================================================================
# Armement et sequence serie — docs/01 §2 et §5.4
# =============================================================================

func test_la_sequence_d_armement_en_distance_respecte_l_ordre_impose() -> void:
	var config := _config(RaceConfig.Mode.DISTANCE, [0, 1])
	config.distance_m = 100.0
	assert_true(_engine.arm(config, 0))
	assert_eq(_commands, ["d", "l278", "g"], "d ou x, puis l ou t, puis g")


func test_les_modes_temps_et_poursuite_emettent_la_constante_sure_t60() -> void:
	# docs/01 §5.5 : la duree demandee n'est JAMAIS transmise au firmware.
	for mode: RaceConfig.Mode in [RaceConfig.Mode.TIME, RaceConfig.Mode.PURSUIT]:
		_commands.clear()
		var engine := RaceEngine.new()
		engine.command_requested.connect(func(c: String) -> void: _commands.append(c))
		var config := _config(mode, [0, 1])
		config.duration_s = 600.0  # valeur qui casserait le firmware si transmise
		assert_true(engine.arm(config, 0))
		assert_eq(_commands, ["x", "t60", "g"])


func test_une_configuration_invalide_n_emet_aucune_commande() -> void:
	# Mieux vaut refuser bruyamment que d'envoyer une valeur que le firmware
	# interpretera de travers.
	var config := _config(RaceConfig.Mode.DISTANCE, [])
	assert_false(_engine.arm(config, 0))
	assert_eq(_commands, [], "aucune commande ne doit partir")
	assert_string_contains(_engine.last_error(), "piste")


func test_une_distance_hors_bornes_est_refusee() -> void:
	var config := _config(RaceConfig.Mode.DISTANCE, [0, 1])
	config.distance_m = 9000.0
	assert_false(_engine.arm(config, 0))
	assert_string_contains(_engine.last_error(), "bornes")


func test_le_timeout_d_armement_est_de_2_s_et_renvoie_a_idle() -> void:
	# docs/02 : 1 s etait un faux negatif systematique, le premier CD: arrivant
	# juste apres 1000 ms.
	assert_true(_engine.arm(_config(RaceConfig.Mode.DISTANCE, [0, 1]), 0))
	assert_eq(_engine.state(), RaceEngine.State.ARMING)
	_engine.tick(1900)
	assert_eq(_engine.state(), RaceEngine.State.ARMING, "1,9 s : on attend encore")
	_engine.tick(2100)
	assert_eq(_engine.state(), RaceEngine.State.IDLE)
	assert_string_contains(_engine.last_error(), "CD:")
	assert_has(_commands, "s", "un armement rate doit remettre le firmware au repos")


# =============================================================================
# LE bug historique de la v1 — docs/01 §5.1
# =============================================================================

func test_course_distance_a_2_riders_qui_se_termine() -> void:
	# Le test le plus important du lot 2. Le firmware attend les QUATRE pistes
	# et ne conclut jamais a deux riders ; c'est le PC qui tranche, en ne
	# comptant que les pistes ACTIVES.
	var config := _config(RaceConfig.Mode.DISTANCE, [0, 1])
	config.distance_m = 100.0
	assert_true(_engine.arm(config, 0))
	_countdown()
	assert_eq(_engine.state(), RaceEngine.State.RUNNING)

	_run_race(20.0, [45.0, 43.0])

	assert_eq(_engine.state(), RaceEngine.State.FINISHED, "la course DOIT se terminer")
	assert_not_null(_result)
	assert_eq(_result.ranking, [0, 1], "le plus rapide gagne")
	assert_eq(_finishes.size(), 2)
	assert_has(_commands, "s", "le PC envoie `s` quand LUI decide que c'est fini")
	assert_false(_result.interrupted)

	# 100 m a 45 km/h = 8,0 s ; a 43 km/h = 8,37 s. Marge large : le tick est
	# quantifie a 35,9 cm.
	assert_between(_result.finished_ms[0], 7900, 8200)
	assert_between(_result.finished_ms[1], 8300, 8600)


func test_les_pistes_inactives_sont_ignorees_partout() -> void:
	# Une piste non declaree qui produirait des ticks — capteur parasite,
	# rebond — ne doit ni apparaitre au classement, ni retarder la fin.
	var config := _config(RaceConfig.Mode.DISTANCE, [0, 1])
	config.distance_m = 100.0
	_engine.arm(config, 0)
	_countdown()
	_run_race(20.0, [45.0, 43.0, 60.0, 60.0])

	assert_eq(_engine.state(), RaceEngine.State.FINISHED)
	assert_eq(_result.ranking.size(), 2)
	assert_false(_result.ranking.has(2))
	assert_eq(_result.finished_ms[2], 0)


func test_course_distance_a_4_riders() -> void:
	var config := _config(RaceConfig.Mode.DISTANCE, [0, 1, 2, 3])
	config.distance_m = 100.0
	_engine.arm(config, 0)
	_countdown()
	_run_race(25.0, [46.0, 45.0, 44.0, 43.0])

	assert_eq(_engine.state(), RaceEngine.State.FINISHED)
	assert_eq(_result.ranking, [0, 1, 2, 3])
	for rider: int in range(4):
		assert_eq(_result.rank_of(rider), rider + 1)


func test_course_distance_a_1_rider() -> void:
	var config := _config(RaceConfig.Mode.DISTANCE, [2])
	config.distance_m = 100.0
	_engine.arm(config, 0)
	_countdown()
	_run_race(20.0, [0.0, 0.0, 45.0, 0.0])
	assert_eq(_engine.state(), RaceEngine.State.FINISHED)
	assert_eq(_result.ranking, [2])


func test_le_plafond_de_securite_du_mode_distance() -> void:
	# docs/02 §1 — 10 minutes. Un rider qui s'arrete ne doit pas bloquer la
	# soiree.
	var config := _config(RaceConfig.Mode.DISTANCE, [0, 1])
	config.distance_m = 5000.0
	config.distance_timeout_s = 5.0
	_engine.arm(config, 0)
	_countdown()
	_run_race(10.0, [20.0, 0.0])

	assert_eq(_engine.state(), RaceEngine.State.FINISHED)
	assert_eq(_result.end_reason, RaceRule.EndReason.TIME_CAP)
	assert_true(_result.interrupted, "une course coupee au plafond est INTERROMPUE")
	assert_eq(_result.ranking[0], 0, "le plus avance est classe premier")


# =============================================================================
# Mode TEMPS — docs/02 §2
# =============================================================================

func test_mode_temps_le_pc_seul_decide_de_la_fin() -> void:
	# docs/02 §2 : bornes 10..3600 s. 10 s est le minimum autorise.
	var config := _config(RaceConfig.Mode.TIME, [0, 1])
	config.duration_s = 10.0
	_engine.arm(config, 0)
	_countdown()
	_run_race(13.0, [45.0, 50.0])

	assert_eq(_engine.state(), RaceEngine.State.FINISHED)
	assert_eq(_result.end_reason, RaceRule.EndReason.TIME_ELAPSED)
	assert_eq(_result.ranking, [1, 0], "le plus loin gagne, pas le plus rapide a un instant")
	assert_gt(_result.distance_m[1], _result.distance_m[0])
	assert_between(_result.elapsed_ms, 10000, 10100)


func test_en_mode_temps_l_egalite_des_temps_n_est_pas_un_photo_finish() -> void:
	# Tout le monde « arrive » a l'instant du gong : `finished_ms` est identique
	# pour tous, par construction. `is_dead_heat` y voyait donc un ex aequo pour
	# CHAQUE coureur, et le tableau operateur marquait toute la colonne
	# « photo-finish » a chaque course en temps.
	var config := _config(RaceConfig.Mode.TIME, [0, 1])
	config.duration_s = 10.0
	_engine.arm(config, 0)
	_countdown()
	_run_race(11.0, [45.0, 40.0])

	assert_eq(_result.finished_ms[0], _result.finished_ms[1], "meme gong pour tout le monde")
	assert_false(_result.is_dead_heat(0), "ce n'est pas un photo-finish")
	assert_false(_result.is_dead_heat(1))


func test_le_classement_en_temps_est_deterministe_meme_a_pointe_egale() -> void:
	# docs/02 §2 departage l'ex aequo par la pointe, et se tait si elle est
	# egale aussi. Le tri de Godot n'etant pas stable, le classement pouvait
	# alors changer d'une execution a l'autre.
	var config := _config(RaceConfig.Mode.TIME, [0, 1, 2])
	config.duration_s = 10.0
	_engine.arm(config, 0)
	_countdown()
	_run_race(11.0, [45.0, 45.0, 45.0])

	var state := _engine.race_state()
	assert_eq(state.ticks[0], state.ticks[1], "trois coureurs identiques")
	assert_eq(_result.ranking, [0, 1, 2], "la piste departage, faute de mieux")


func test_le_classement_par_distance_est_deterministe_a_egalite() -> void:
	# « Le plus avance d'abord » etait recopie dans trois fichiers, sans
	# departage. Le tri de Godot n'est pas stable : a distance egale, la regle
	# et l'ecran pouvaient designer des meneurs DIFFERENTS — au plafond de
	# securite, c'est le vainqueur qui change.
	var config := _config(RaceConfig.Mode.PURSUIT, [0, 1, 2])
	var state := RaceState.new(config)
	state.distance_m[0] = 120.0
	state.distance_m[1] = 200.0
	state.distance_m[2] = 200.0

	var order: Array[int] = state.by_distance([0, 1, 2])
	assert_eq(order, [1, 2, 0], "le plus avance d'abord, la piste departage l'egalite")
	assert_eq(state.by_distance([2, 1, 0]), order, "et l'ordre d'entree n'y change rien")
	assert_eq(state.leader(), 1, "le meneur est celui que le classement met en tete")


func test_mode_temps_ex_aequo_departage_par_vitesse_de_pointe() -> void:
	var config := _config(RaceConfig.Mode.TIME, [0, 1])
	config.duration_s = 10.0
	_engine.arm(config, 0)
	_countdown()
	# Meme distance en 10 s — 40 km/h constants contre 30 puis 50 —, mais le
	# rider 1 a eu la pointe la plus elevee. (La version precedente de ce test
	# n'affirmait rien, et ses vitesses ne faisaient meme pas un ex aequo.)
	_run_race(11.0, [40.0, 30.0], 0, [40.0, 50.0], 5.0)
	assert_eq(_engine.state(), RaceEngine.State.FINISHED)
	var state := _engine.race_state()
	assert_eq(state.ticks[0], state.ticks[1], "memes ticks cumules")
	assert_gt(state.max_speed_kph[1], state.max_speed_kph[0])
	assert_eq(_result.ranking, [1, 0], "la pointe departage")


func test_mode_distance_meme_trame_ex_aequo_photo_finish_range_par_piste() -> void:
	# docs/02 §1 : deux riders qui franchissent dans la meme trame sont ex
	# aequo ; ranges par numero de piste, et l'UI le dit. Les pistes sont
	# declarees dans le desordre pour prouver que le tri ne depend pas d'une
	# stabilite que `sort_custom` ne garantit pas.
	var config := _config(RaceConfig.Mode.DISTANCE, [2, 0])
	config.distance_m = 100.0
	_engine.arm(config, 0)
	_countdown()
	_run_race(30.0, [45.0, 0.0, 45.0])
	assert_eq(_engine.state(), RaceEngine.State.FINISHED)
	assert_eq(_result.finished_ms[0], _result.finished_ms[2], "meme trame")
	assert_eq(_result.ranking, [0, 2], "ex aequo : par numero de piste")
	assert_true(_result.is_dead_heat(0), "photo-finish, et l'UI le dira")
	assert_true(_result.is_dead_heat(2))


# =============================================================================
# Mode POURSUITE — docs/02 §3
# =============================================================================

func test_poursuite_2_riders_fin_exacte_au_franchissement_de_l_ecart() -> void:
	var config := _config(RaceConfig.Mode.PURSUIT, [0, 1])
	config.gap_m = 50.0
	_engine.arm(config, 0)
	_countdown()
	# 10 km/h d'ecart = 2,78 m/s. 50 m d'ecart atteints a t = 18,0 s.
	_run_race(30.0, [50.0, 40.0])

	assert_eq(_engine.state(), RaceEngine.State.FINISHED)
	assert_eq(_result.end_reason, RaceRule.EndReason.LAST_ONE_STANDING)
	assert_eq(_result.ranking, [0, 1], "celui qui est devant gagne")
	assert_true(_result.eliminated[1])
	assert_eq(_eliminations.size(), 1)

	# La fin doit tomber au tick pres, pas « quelque part vers 18 s ». Un tick
	# vaut 35,9 cm, soit ~26 ms a cette vitesse relative.
	assert_between(_result.elapsed_ms, 17900, 18200)
	assert_almost_eq(float(_eliminations[0]["gap"]), 50.0, 0.6)


func test_poursuite_4_riders_ordre_d_elimination_progressive() -> void:
	# docs/02 §3 : le dernier sort des qu'il prend G metres au leader, et le
	# rang vaut « riders restants + 1 ».
	var config := _config(RaceConfig.Mode.PURSUIT, [0, 1, 2, 3])
	config.gap_m = 30.0
	_engine.arm(config, 0)
	_countdown()
	_run_race(120.0, [55.0, 50.0, 45.0, 40.0])

	assert_eq(_engine.state(), RaceEngine.State.FINISHED)
	assert_eq(_eliminations.size(), 3, "trois elimines, un survivant")
	assert_eq(_eliminations[0]["rider"], 3, "le plus lent sort en premier")
	assert_eq(_eliminations[1]["rider"], 2)
	assert_eq(_eliminations[2]["rider"], 1)
	assert_eq(_eliminations[0]["rank"], 4)
	assert_eq(_eliminations[1]["rank"], 3)
	assert_eq(_eliminations[2]["rank"], 2)
	assert_eq(_result.ranking, [0, 1, 2, 3])


func test_poursuite_plafond_de_duree() -> void:
	# Deux riders de niveau egal courraient jusqu'a epuisement sans ce plafond.
	var config := _config(RaceConfig.Mode.PURSUIT, [0, 1])
	config.gap_m = 500.0
	config.pursuit_time_cap_s = 6.0
	_engine.arm(config, 0)
	_countdown()
	_run_race(10.0, [45.0, 44.5])

	assert_eq(_engine.state(), RaceEngine.State.FINISHED)
	assert_eq(_result.end_reason, RaceRule.EndReason.TIME_CAP)
	assert_true(_result.interrupted)
	assert_eq(_result.ranking[0], 0, "celui qui mene a cet instant gagne")


func test_poursuite_plafond_de_distance() -> void:
	var config := _config(RaceConfig.Mode.PURSUIT, [0, 1])
	config.gap_m = 500.0
	config.pursuit_time_cap_s = 3600.0
	config.pursuit_distance_cap_m = 100.0
	_engine.arm(config, 0)
	_countdown()
	_run_race(30.0, [45.0, 44.0])

	assert_eq(_engine.state(), RaceEngine.State.FINISHED)
	assert_eq(_result.end_reason, RaceRule.EndReason.DISTANCE_CAP)
	assert_true(_result.interrupted)


func test_poursuite_le_temps_avant_decision_est_visible_a_l_ecran() -> void:
	# docs/02 §3 : les plafonds « doivent etre visibles dans l'UI (jauge
	# temps restant avant decision) ». Le moteur fournit la valeur.
	var config := _config(RaceConfig.Mode.PURSUIT, [0, 1])
	config.gap_m = 500.0
	config.pursuit_time_cap_s = 100.0
	config.pursuit_distance_cap_m = 5000.0
	_engine.arm(config, 0)
	_countdown()
	_run_race(10.0, [45.0, 44.5])
	var state := _engine.race_state()
	assert_almost_eq(RulePursuit.seconds_before_decision(state), 90.0, 0.1)
	# 10 s a 45 km/h = 125 m : il en reste 4875 avant le plafond de distance.
	assert_almost_eq(RulePursuit.metres_before_decision(state), 4875.0, 2.0)
	assert_eq(RulePursuit.decision_text(state), "decision dans 1:30")

	# Quand c'est la distance qui tranchera en premier, c'est elle qu'on montre.
	# (Le moteur travaille sur SA copie de la configuration.)
	state.config.pursuit_distance_cap_m = 200.0
	assert_eq(RulePursuit.decision_text(state), "decision a 75 m")


func test_poursuite_la_tension_mesure_la_progression_vers_la_decision() -> void:
	var config := _config(RaceConfig.Mode.PURSUIT, [0, 1])
	config.gap_m = 50.0
	_engine.arm(config, 0)
	_countdown()
	_run_race(9.0, [50.0, 40.0])
	var pursuit := _engine.rule() as RulePursuit
	assert_almost_eq(pursuit.tension(_engine.race_state()), 0.5, 0.1)


# =============================================================================
# Faux depart — docs/02 §4
# =============================================================================

func test_faux_depart_avertissement_la_course_continue() -> void:
	var config := _config(RaceConfig.Mode.DISTANCE, [0, 1])
	config.distance_m = 100.0
	config.false_start_policy = RaceConfig.FalseStartPolicy.WARN
	_engine.arm(config, 0)
	_engine.on_countdown(3)
	_engine.on_false_start(0)
	_engine.on_countdown(0)
	assert_eq(_engine.state(), RaceEngine.State.RUNNING, "AVERTISSEMENT ne relance pas")
	assert_true(_engine.race_state().false_started[0])


func test_faux_depart_relance_avorte_la_course() -> void:
	var config := _config(RaceConfig.Mode.DISTANCE, [0, 1])
	config.false_start_policy = RaceConfig.FalseStartPolicy.RESTART
	_engine.arm(config, 0)
	_engine.on_countdown(3)
	_commands.clear()
	_engine.on_false_start(1)
	assert_eq(_engine.state(), RaceEngine.State.IDLE)
	assert_has(_commands, "s")


func test_faux_depart_penalite_applique_un_handicap_en_metres() -> void:
	var config := _config(RaceConfig.Mode.DISTANCE, [0, 1])
	config.distance_m = 100.0
	config.false_start_policy = RaceConfig.FalseStartPolicy.PENALTY
	config.false_start_penalty_m = 10.0
	_engine.arm(config, 0)
	_engine.on_countdown(3)
	_engine.on_false_start(0)
	_engine.on_countdown(0)
	_run_race(2.0, [45.0, 45.0])

	var state := _engine.race_state()
	assert_almost_eq(state.distance_m[1] - state.distance_m[0], 10.0, 0.5)


func test_un_faux_depart_sur_une_piste_inactive_est_ignore() -> void:
	var config := _config(RaceConfig.Mode.DISTANCE, [0, 1])
	config.false_start_policy = RaceConfig.FalseStartPolicy.RESTART
	_engine.arm(config, 0)
	_engine.on_countdown(3)
	_engine.on_false_start(3)
	assert_eq(_engine.state(), RaceEngine.State.COUNTDOWN, "piste 3 non declaree")


# =============================================================================
# Filtrage des ticks aberrants — docs/01 §6.3
# =============================================================================

func test_un_tick_impliquant_plus_de_120_kmh_est_rejete_et_loggue() -> void:
	var config := _config(RaceConfig.Mode.TIME, [0, 1])
	config.duration_s = 60.0
	_engine.arm(config, 0)
	_countdown()

	# 10 ticks en 1 s = 12,9 km/h : plausible.
	_engine.on_progress([10, 10, 0, 0], 1000)
	# +290 ticks en 10 ms = 104 m en 10 ms, soit ~37 500 km/h.
	_engine.on_progress([300, 10, 0, 0], 1010)

	assert_eq(_rejections.size(), 1, "le rejet doit etre visible, jamais silencieux")
	assert_string_contains(_rejections[0], "km/h")
	assert_eq(_engine.race_state().ticks[0], 10, "la derniere valeur SAINE est conservee")


func test_un_compteur_de_ticks_qui_recule_est_rejete() -> void:
	var config := _config(RaceConfig.Mode.TIME, [0, 1])
	_engine.arm(config, 0)
	_countdown()
	_engine.on_progress([10, 10, 0, 0], 1000)
	_engine.on_progress([8, 10, 0, 0], 1010)
	assert_eq(_rejections.size(), 1)
	assert_string_contains(_rejections[0], "recul")
	assert_eq(_engine.race_state().ticks[0], 10)


func test_une_horloge_firmware_qui_recule_fait_rejeter_la_trame_entiere() -> void:
	var config := _config(RaceConfig.Mode.TIME, [0, 1])
	_engine.arm(config, 0)
	_countdown()
	_engine.on_progress([20, 20, 0, 0], 2000)
	_engine.on_progress([21, 21, 0, 0], 1500)
	assert_eq(_rejections.size(), 1)
	assert_eq(_engine.race_state().ticks[0], 20)


func test_une_valeur_rejetee_est_rattrapee_par_la_trame_suivante() -> void:
	# docs/01 §3 : les valeurs de R: sont ABSOLUES. Perdre une trame est sans
	# effet — c'est ce qui rend le systeme robuste, et il faut le preserver.
	var config := _config(RaceConfig.Mode.TIME, [0, 1])
	_engine.arm(config, 0)
	_countdown()
	_engine.on_progress([10, 10, 0, 0], 1000)
	_engine.on_progress([9000, 10, 0, 0], 1010)
	assert_eq(_engine.race_state().ticks[0], 10)
	_engine.on_progress([11, 10, 0, 0], 1020)
	assert_eq(_engine.race_state().ticks[0], 11, "le flux repart sans intervention")


# =============================================================================
# FSM — docs/06 §1 : aucun etat mort
# =============================================================================

func test_chaque_etat_de_la_fsm_est_atteint() -> void:
	var config := _config(RaceConfig.Mode.DISTANCE, [0, 1])
	config.distance_m = 100.0
	assert_eq(_engine.state(), RaceEngine.State.IDLE)
	_engine.arm(config, 0)
	_countdown()
	_run_race(20.0, [45.0, 44.0])
	_engine.show_results()
	assert_eq(_engine.state(), RaceEngine.State.RESULTS)
	_engine.acknowledge_results()
	assert_eq(_engine.state(), RaceEngine.State.IDLE)

	for wanted: int in [
		RaceEngine.State.ARMING,
		RaceEngine.State.COUNTDOWN,
		RaceEngine.State.RUNNING,
		RaceEngine.State.FINISHED,
		RaceEngine.State.RESULTS,
		RaceEngine.State.IDLE,
	]:
		assert_has(_states, wanted, "etat %s jamais atteint" % RaceEngine.State.keys()[wanted])


func test_un_abandon_operateur_coupe_la_course_et_envoie_s() -> void:
	_engine.arm(_config(RaceConfig.Mode.DISTANCE, [0, 1]), 0)
	_countdown()
	_commands.clear()
	_engine.abort("arret operateur")
	assert_eq(_engine.state(), RaceEngine.State.IDLE)
	assert_has(_commands, "s")


func test_une_perte_de_lien_prolongee_avorte_la_course() -> void:
	# docs/01 §6.2 : au-dela du delai de grace, la course est perdue.
	_engine.arm(_config(RaceConfig.Mode.DISTANCE, [0, 1]), 0)
	_countdown()
	_commands.clear()
	_engine.on_link_lost_beyond_grace()
	assert_eq(_engine.state(), RaceEngine.State.IDLE)
	assert_has(_commands, "s")


func test_on_ne_peut_pas_armer_deux_courses_a_la_fois() -> void:
	_engine.arm(_config(RaceConfig.Mode.DISTANCE, [0, 1]), 0)
	_commands.clear()
	assert_false(_engine.arm(_config(RaceConfig.Mode.TIME, [0, 1]), 0))
	assert_eq(_commands, [])


func test_le_firmware_f_est_une_confirmation_jamais_une_condition_de_fin() -> void:
	# docs/01 §5.4 : le firmware ne connait pas les pistes actives. Ses <i>F:
	# ne doivent JAMAIS terminer une course cote PC.
	var config := _config(RaceConfig.Mode.DISTANCE, [0, 1])
	config.distance_m = 1000.0
	_engine.arm(config, 0)
	_countdown()
	_engine.on_progress([10, 10, 0, 0], 1000)
	_engine.on_rider_finish(0, 1000)
	_engine.on_rider_finish(1, 1000)
	assert_eq(_engine.state(), RaceEngine.State.RUNNING, "la course continue")
	assert_eq(_finishes.size(), 0)


func test_une_pointe_humainement_invraisemblable_est_signalee() -> void:
	# DEPANNAGE : « une pointe au-dessus de 90 km/h n'est pas une performance,
	# c'est un capteur qui rebondit ou un aimant qui passe deux fois par tour ».
	# La fiche demandait a l'operateur de le remarquer ; le moteur le voit.
	#
	# A distinguer du FILTRE (docs/01 §6.3, 120 km/h) : celui-la REJETTE
	# l'impossible. Ici la mesure est retenue — elle est peut-etre vraie — et
	# seulement signalee comme suspecte.
	var suspects: Array = []
	_engine.speed_implausible.connect(func(rider: int, kph: float) -> void:
		suspects.append([rider, kph]))
	var config := _config(RaceConfig.Mode.DISTANCE, [0, 1])
	config.distance_m = 300.0
	_engine.arm(config, 0)
	_countdown()
	_run_race(6.0, [100.0, 45.0])

	assert_eq(suspects.size(), 1, "une seule alerte, pour la seule piste concernee")
	assert_eq(int((suspects[0] as Array)[0]), 0, "c'est la piste 1")
	assert_gt(float((suspects[0] as Array)[1]), Physics.SUSPECT_PEAK_KPH)
	assert_true(_rejections.is_empty(), "et rien n'a ete rejete : la mesure est retenue")


func test_la_vitesse_de_pointe_reste_plausible() -> void:
	# Constate sur la premiere course complete menee a l'interface : la pointe
	# etait calculee sur la vitesse instantanee, ce qui donnait 117 km/h pour un
	# cycliste a 45. A 100 Hz, un tick vaut 35,9 cm : un seul tick sur une trame
	# de 10 ms « vaut » 129 km/h.
	var config := _config(RaceConfig.Mode.TIME, [0, 1])
	config.duration_s = 12.0
	_engine.arm(config, 0)
	_countdown()
	_run_race(14.0, [45.0, 30.0])

	assert_eq(_engine.state(), RaceEngine.State.FINISHED)
	for rider: int in [0, 1]:
		var expected: float = [45.0, 30.0][rider]
		var peak := _result.max_kph[rider]
		var mean := _result.avg_kph[rider]
		assert_between(peak, expected * 0.9, expected * 1.15,
			"la pointe doit encadrer la vitesse reelle de la piste %d" % rider)
		assert_gt(peak, mean, "la pointe depasse la moyenne")
		assert_lt(peak, Physics.MAX_PLAUSIBLE_KPH, "et reste sous le plafond du filtre")


# =============================================================================
# La derniere trame `R:` n'arrive JAMAIS — docs/01 §5.6
#
# `ss_basic.ino` (`checkDistanceBased`, l. 285-307) met `raceStarted = false`
# dans la passe meme ou le dernier tick fait franchir la ligne, et l'emission
# periodique des trames `R:` est conditionnee par `raceStarted`. La valeur qui
# atteint la cible n'est donc jamais transmise. Sans traitement, le PC reste
# bloque un tick en dessous et la course ne se termine pas.
# =============================================================================


func test_la_course_se_termine_meme_si_la_derniere_trame_manque() -> void:
	var config := _config(RaceConfig.Mode.DISTANCE, [0, 1])
	config.distance_m = 500.0
	assert_true(_engine.arm(config, _now_ms), "armement accepte")
	_countdown()

	var physics := Physics.new()
	var target := physics.metres_to_ticks(config.distance_m)
	assert_eq(target, 1392, "500 m valent 1392 ticks au rouleau de 114,3 mm")

	# Le boitier s'arrete un tick avant la cible pour la piste 1 : c'est
	# exactement ce que fait le firmware reel.
	_engine.on_progress([target, target - 1, 0, 0], 40_000)
	assert_eq(_finishes.size(), 1, "seule la piste 0 a franchi la ligne")
	assert_eq(_engine.state(), RaceEngine.State.RUNNING, "la course attend encore la piste 1")

	# Puis il annonce l'arrivee par `1F:`. C'est la seule trace qu'il reste du
	# dernier tick.
	_engine.on_rider_finish(1, 40_000)

	assert_eq(_finishes.size(), 2, "la piste 1 est declaree arrivee")
	assert_eq(int(_finishes[1]["rider"]), 1, "et c'est bien la piste 1")
	assert_ne(_engine.state(), RaceEngine.State.RUNNING, "la course ne tourne plus")
	var state := _engine.race_state()
	assert_eq(state.ticks[1], target, "son compte est remonte a la cible")


func test_une_trame_de_fin_trop_en_avance_est_refusee() -> void:
	var config := _config(RaceConfig.Mode.DISTANCE, [0, 1])
	config.distance_m = 500.0
	assert_true(_engine.arm(config, _now_ms), "armement accepte")
	_countdown()

	# A mi-course, une trame `1F:` ne peut etre qu'une aberration : la refuser
	# vaut mieux que terminer une course sur une donnee douteuse.
	_engine.on_progress([700, 700, 0, 0], 20_000)
	_engine.on_rider_finish(1, 20_000)

	assert_eq(_finishes.size(), 0, "aucune arrivee declaree")
	assert_eq(_engine.state(), RaceEngine.State.RUNNING, "la course continue")
	assert_eq(_engine.race_state().ticks[1], 700, "le compte n'a pas ete gonfle")


func test_une_trame_de_fin_sur_une_piste_inactive_est_ignoree() -> void:
	var config := _config(RaceConfig.Mode.DISTANCE, [0, 1])
	config.distance_m = 500.0
	assert_true(_engine.arm(config, _now_ms), "armement accepte")
	_countdown()

	# Le firmware ignore quelles pistes sont actives et annonce les quatre
	# (docs/01 §5.4) : le PC, lui, ne connait que les siennes.
	_engine.on_progress([1391, 1391, 0, 0], 40_000)
	_engine.on_rider_finish(3, 40_000)

	assert_eq(_finishes.size(), 0, "la piste 3 n'est pas de la course")
	assert_eq(_engine.state(), RaceEngine.State.RUNNING, "la course continue")


# =============================================================================
# Elimination : l'instant est memorise, et la moyenne s'arrete la
# =============================================================================


func test_la_moyenne_d_un_elimine_s_arrete_a_son_elimination() -> void:
	var config := _config(RaceConfig.Mode.PURSUIT, [0, 1])
	config.gap_m = 20.0
	assert_true(_engine.arm(config, _now_ms), "armement accepte")
	_countdown()

	# Piste 0 a 50 km/h, piste 1 a 25 : l'ecart de 20 m est atteint vers 2,9 s.
	_run_race(30.0, [50.0, 25.0])
	assert_eq(_eliminations.size(), 1, "la piste 1 est eliminee")
	assert_eq(int(_eliminations[0]["rider"]), 1)

	var state := _engine.race_state()
	assert_gt(state.eliminated_ms[1], 0, "l'instant de l'elimination est memorise")
	assert_eq(state.eliminated_ms[0], 0, "le survivant n'en a pas")

	assert_not_null(_result, "la course est terminee")
	# La distance de la piste 1 est figee a l'elimination : sa moyenne doit se
	# calculer sur CE temps-la, pas sur la duree totale de la course.
	var expected := _result.distance_m[1] / (float(_result.eliminated_ms[1]) / 1000.0) * 3.6
	assert_almost_eq(_result.avg_kph[1], expected, 0.01, "moyenne sur le temps couru")
	assert_gt(_result.avg_kph[1], 20.0, "proche des 25 km/h reels, pas diluee")


func test_chaque_etat_a_un_libelle_lisible_par_un_operateur() -> void:
	# Les noms d'enum viennent du diagramme de `docs/02` §1, qui est un document
	# de CONCEPTION : ils n'apparaissent nulle part dans le manuel de
	# l'operateur. Ce qui s'affiche doit dire ce qui se passe.
	for state: int in RaceEngine.State.values():
		var label := RaceEngine.state_label(state)
		assert_false(label.is_empty(), "l'etat %d a un libelle" % state)
		assert_ne(
			label, RaceEngine.State.keys()[state],
			"l'etat %s ne s'affiche pas sous son nom de code" % RaceEngine.State.keys()[state]
		)
		assert_eq(label, label.to_lower(), "en minuscules, comme une phrase")
	assert_string_contains(RaceEngine.state_label(RaceEngine.State.IDLE), "repos")
	assert_string_contains(RaceEngine.state_label(RaceEngine.State.RUNNING), "course en cours")


func test_un_refus_d_armement_nomme_l_etat_en_francais() -> void:
	var engine := RaceEngine.new()
	var config := RaceConfig.new()
	assert_true(engine.arm(config, 0), "le premier armement passe")
	assert_false(engine.arm(config, 0), "le second est refuse")
	assert_false(engine.last_error().is_empty(), "le second armement est refuse")
	assert_false(
		engine.last_error().contains("ARMING"), "pas de nom de code dans un message d'erreur"
	)
	assert_string_contains(engine.last_error(), RaceEngine.state_label(engine.state()))


func test_aucun_etat_de_la_fsm_n_est_mort() -> void:
	# docs/06 §1, regle 4. Le lien serie avait ce test depuis longtemps
	# (`test_link_sim.gd`) ; la FSM de course, qui est pourtant celle qui arbitre
	# les classements, ne l'avait pas. Un scenario complet doit les traverser
	# tous les six.
	var seen: Array[int] = []
	var engine := RaceEngine.new()
	engine.state_changed.connect(
		func(_previous: int, current: int) -> void:
			if not seen.has(current):
				seen.append(current)
	)
	var config := RaceConfig.new()
	config.distance_m = 50.0
	assert_true(engine.arm(config, 0), "armement")
	engine.on_countdown(3)
	engine.on_countdown(0)
	var ticks := 0
	for step: int in range(400):
		ticks += 6
		engine.on_progress([ticks, ticks - 2, 0, 0], step * 100)
		if engine.state() == RaceEngine.State.FINISHED:
			break
	assert_eq(engine.state(), RaceEngine.State.FINISHED, "la course se termine")
	engine.show_results()
	engine.acknowledge_results()

	seen.append(RaceEngine.State.IDLE)  # l'etat de depart, jamais « change vers »
	for state: int in RaceEngine.State.values():
		assert_has(
			seen, state,
			"l'etat %s n'est atteint par aucun scenario" % RaceEngine.State.keys()[state]
		)
