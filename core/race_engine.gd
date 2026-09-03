## Moteur de course — la FSM de docs/02 et l'arbitrage de docs/01 §5.4.
##
## LE POINT QUI STRUCTURE TOUT LE FICHIER : **le PC est autoritaire**. Le
## firmware est un capteur. Il fournit un flux de ticks cumules horodates,
## cadence le decompte et pilote les LED — rien d'autre. Condition de fin,
## classement, elimination, ecarts, disqualification : tout est calcule ici, et
## c'est ce moteur qui envoie `s` quand LUI decide que c'est fini.
##
## `core/` ne connait ni la scene, ni le port serie, ni le rendu. Le moteur
## n'emet pas de commandes serie : il emet `command_requested`, que la couche
## applicative relaie. C'est ce qui permet de le tester entierement en headless.
class_name RaceEngine
extends RefCounted

signal state_changed(previous: State, current: State)
## Commande serie a emettre. La couche applicative la relaie au lien.
signal command_requested(command: String)
signal countdown_tick(value: int)
signal race_started()
signal rider_finished(rider: int, elapsed_ms: int, rank: int)
signal rider_eliminated(rider: int, rank: int, gap_m: float)
signal false_start_detected(rider: int, policy: RaceConfig.FalseStartPolicy)
## `rider` vaut -1 quand le rejet ne concerne pas une piste (horloge en recul).
signal tick_rejected(rider: int, description: String)
## Pointe humainement invraisemblable — signalee UNE FOIS par piste et par
## course, sans rien rejeter. `DEPANNAGE` demandait a l'operateur de la
## remarquer lui-meme dans les resultats, une fois la course finie.
signal speed_implausible(rider: int, kph: float)
signal race_finished(result: RaceResult)
signal race_aborted(note: String)
signal progress_updated(state: RaceState)

## docs/02 — FSM exhaustive. Chaque etat est atteint par au moins un test
## (docs/06 §1) : un etat non atteignable est un bug de conception, comme le
## `GO` orphelin de la v2.
enum State {
	IDLE,  ## au repos, prêt a armer
	ARMING,  ## commandes emises, on attend le premier CD:
	COUNTDOWN,  ## decompte en cours
	RUNNING,  ## course en cours, arbitrage actif
	FINISHED,  ## le PC a decide : `s` emis, classement fige
	RESULTS,  ## resultat consultable, en attente d'acquittement
}

## docs/02 — timeout d'armement. 2 s et non 1 s : le firmware n'emet `CD:3`
## qu'apres 1000 ms, plus la latence serie.
const ARMING_TIMEOUT_MS := 2000

var _state: State = State.IDLE
var _config: RaceConfig = null
var _race_state: RaceState = null
var _rule: RaceRule = null
var _filter: TickFilter = null
var _result: RaceResult = null
var _armed_at_ms: int = -1
var _last_error: String = ""
var _interrupted: bool = false
## Pistes deja signalees pour une pointe suspecte — une alerte par course.
var _suspect_peaks: Array[int] = []
var _interruption_note: String = ""


func state() -> State:
	return _state


## Nom de CODE de l'etat — pour les journaux et les outils de diagnostic, qui
## parlent le langage du diagramme de `docs/02` §1.
func state_name() -> String:
	return State.keys()[_state]


## Ce que l'operateur lit. Les noms d'enum viennent d'un document de
## CONCEPTION : « Etat : IDLE » n'apprend rien a qui tient la souris un soir de
## course, et ces six mots n'apparaissent nulle part dans le manuel. Le libelle
## dit ce qui se passe, et quand c'est utile ce qu'on attend — voir la table du
## MANUEL, qui est la meme.
static func state_label(state: State) -> String:
	match state:
		State.IDLE:
			return "au repos — prêt à lancer"
		State.ARMING:
			return "armement — le boîtier doit répondre"
		State.COUNTDOWN:
			return "décompte"
		State.RUNNING:
			return "course en cours"
		State.FINISHED:
			return "arrivée — classement figé"
		State.RESULTS:
			return "résultat affiché — à acquitter"
	return "état inconnu"


func race_state() -> RaceState:
	return _race_state


func rule() -> RaceRule:
	return _rule


func result() -> RaceResult:
	return _result


func last_error() -> String:
	return _last_error


## Arme une course. Rend false si la configuration est invalide — dans ce cas
## AUCUNE commande n'est emise : mieux vaut refuser bruyamment que d'envoyer au
## firmware une valeur qu'il interpretera de travers.
func arm(config: RaceConfig, now_ms: int) -> bool:
	_last_error = ""
	if _state != State.IDLE:
		_last_error = "impossible d'armer depuis l'état « %s »" % state_label(_state)
		return false
	var problems := config.validate()
	if not problems.is_empty():
		_last_error = ", ".join(problems)
		return false

	_config = config.duplicate_config()
	_race_state = RaceState.new(_config)
	_filter = TickFilter.new(_race_state.physics)
	_rule = _make_rule(_config.mode)
	_result = null
	_interrupted = false
	_interruption_note = ""
	_suspect_peaks.clear()
	_armed_at_ms = now_ms

	_set_state(State.ARMING)
	for command: String in _config.arming_commands():
		command_requested.emit(command)
	return true


## Horloge PC — utilisee UNIQUEMENT pour les delais d'attente. Elle ne date
## jamais la course : c'est `elapsedMs` du firmware qui fait foi (docs/01 §3).
func tick(now_ms: int) -> void:
	if _state == State.ARMING and now_ms - _armed_at_ms > ARMING_TIMEOUT_MS:
		_fail_arming("aucun CD: reçu après %d ms" % ARMING_TIMEOUT_MS)


## Trame `CD:<n>` du firmware.
func on_countdown(value: int) -> void:
	if _state == State.ARMING:
		_set_state(State.COUNTDOWN)
	if _state != State.COUNTDOWN:
		return
	countdown_tick.emit(value)
	if value <= 0:
		_begin_running()


## Trame `R:` — deja validee par le parseur, pas encore filtree.
func on_progress(ticks: Array, elapsed_ms: int) -> void:
	# Le firmware peut emettre sa premiere trame R: avant que CD:0 nous
	# parvienne : la trame fait foi, elle prouve que la course a demarre.
	if _state == State.COUNTDOWN:
		_begin_running()
	if _state != State.RUNNING:
		return

	var before := _filter.rejection_count()
	var accepted := _filter.accept(ticks, elapsed_ms, _config.active_riders)
	for i: int in range(before, _filter.rejection_count()):
		var rejection := _filter.rejections()[i]
		tick_rejected.emit(rejection.rider, rejection.describe())

	_race_state.apply_sample(accepted, elapsed_ms)
	_flag_implausible_peaks()
	progress_updated.emit(_race_state)
	_apply_verdict(_rule.evaluate(_race_state))


## Trame `FS:<idx>` — docs/02 §4. Le firmware se contente de signaler ; c'est
## ici que la politique s'applique.
func on_false_start(rider: int) -> void:
	if _state != State.COUNTDOWN and _state != State.ARMING:
		return
	if rider < 0 or rider >= Protocol.MAX_RIDERS:
		return
	if not _config.active_riders.has(rider):
		return  # une piste non declaree qui bouge n'est pas un faux depart
	if _race_state.false_started[rider]:
		return

	_race_state.false_started[rider] = true
	false_start_detected.emit(rider, _config.false_start_policy)

	match _config.false_start_policy:
		RaceConfig.FalseStartPolicy.RESTART:
			# NUMERO DE PISTE HUMAIN, 1..4, comme partout a l'ecran. L'indice
			# brut partait dans le motif d'interruption — donc au bandeau
			# public, a la note du CSV, au tableau de l'operateur et a
			# l'historique du jour : un faux depart sur la piste 2 accusait
			# publiquement « piste 1 ». `tick_filter.gd` porte la meme regle,
			# commentee, depuis toujours.
			abort("faux départ piste %d" % (rider + 1))
		RaceConfig.FalseStartPolicy.PENALTY:
			# Handicap : le rider fautif demarre `P` metres en arriere.
			_race_state.handicap_m[rider] = -_config.false_start_penalty_m
		_:
			pass  # IGNORE et AVERTISSEMENT laissent la course partir


## Trame `<idx>F:` — CONFIRMATION uniquement. Jamais une condition de fin :
## le firmware ne connait pas les pistes actives (docs/01 §5.4).
func on_rider_finish(rider: int, _elapsed_ms: int) -> void:
	if _state != State.RUNNING or _rule == null or _race_state == null:
		return
	# L'horodatage du boitier est ignore : le classement et les temps restent
	# calcules par le PC, sur son propre relevé. Seule l'information « ce
	# coureur a franchi la ligne » est retenue.
	if not _rule.note_hardware_finish(_race_state, rider):
		return
	progress_updated.emit(_race_state)
	_apply_verdict(_rule.evaluate(_race_state))


## Arret demande par l'operateur, ou impose (lien perdu, faux depart).
func abort(note: String) -> void:
	if _state == State.IDLE or _state == State.RESULTS:
		return
	command_requested.emit("s")
	_interrupted = true
	_interruption_note = note
	# UNE COURSE QUI A COURU GARDE SON RESULTAT PARTIEL. C'est lui qui porte
	# la trace au disque : sans lui, les trames deja recues etaient jetees et
	# l'incident — lien perdu, arrêt opérateur — devenait le seul cas
	# NON rejouable, alors que c'est celui qu'on veut debriefer.
	#
	# Interrompue pendant l'armement ou le decompte, elle n'a rien a raconter.
	_result = null
	if _state == State.RUNNING and _race_state != null and _rule != null:
		var final_order := _rule.final_ranking(_race_state)
		for position: int in range(final_order.size()):
			_race_state.rank[final_order[position]] = position + 1
		_result = RaceResult.from_state(_race_state, _rule, RaceRule.EndReason.NONE)
		_result.interrupted = true
		_result.interruption_note = note
	race_aborted.emit(note)
	_set_state(State.IDLE)


## Le lien est perdu au-dela du delai de grace — docs/01 §6.2.
func on_link_lost_beyond_grace() -> void:
	if _state == State.RUNNING or _state == State.COUNTDOWN:
		abort("lien perdu au-delà du délai de grâce")


## Passe de FINISHED a RESULTS : l'operateur a vu le classement.
func show_results() -> void:
	if _state == State.FINISHED:
		_set_state(State.RESULTS)


## Referme l'ecran de resultats et revient au repos.
func acknowledge_results() -> void:
	if _state == State.RESULTS:
		_set_state(State.IDLE)


# --- Interne -----------------------------------------------------------------

func _make_rule(mode: RaceConfig.Mode) -> RaceRule:
	match mode:
		RaceConfig.Mode.DISTANCE:
			return RuleDistance.new()
		RaceConfig.Mode.TIME:
			return RuleTime.new()
		RaceConfig.Mode.PURSUIT:
			return RulePursuit.new()
	return RuleDistance.new()


func _begin_running() -> void:
	_rule.begin(_race_state)
	_set_state(State.RUNNING)
	race_started.emit()


func _fail_arming(reason: String) -> void:
	_last_error = reason
	command_requested.emit("s")
	race_aborted.emit(reason)
	_set_state(State.IDLE)


func _apply_verdict(verdict: RaceRule.Verdict) -> void:
	# Les eliminations d'ABORD. A la derniere trame d'une poursuite, le meme
	# verdict porte l'elimination du dernier ET l'arrivee du vainqueur ; traiter
	# l'arrivee en premier faisait sortir le dernier avec le rang 1. Les
	# elimines se classent par le bas, les arrives par le haut : les deux
	# comptages ne doivent pas se marcher dessus.
	for entry: Dictionary in verdict.newly_eliminated:
		var rider := int(entry["rider"])
		if _race_state.eliminated[rider]:
			continue
		var rank := _race_state.next_elimination_rank()
		_race_state.eliminated[rider] = true
		_race_state.eliminated_ms[rider] = _race_state.elapsed_ms
		if _rule is RulePursuit:
			(_rule as RulePursuit).note_elimination(rider)
		_race_state.rank[rider] = rank
		rider_eliminated.emit(rider, rank, float(entry["gap_m"]))

	for entry: Dictionary in verdict.newly_finished:
		var rider := int(entry["rider"])
		if _race_state.finished_ms[rider] != 0:
			continue
		var rank := _race_state.next_finish_rank()
		_race_state.finished_ms[rider] = int(entry["elapsed_ms"])
		_race_state.rank[rider] = rank
		rider_finished.emit(rider, _race_state.finished_ms[rider], rank)

	if verdict.race_over:
		_finish(verdict.reason)


func _finish(reason: RaceRule.EndReason) -> void:
	# C'est ICI que le PC exerce son autorite : il decide, puis il le dit au
	# firmware. Jamais l'inverse.
	command_requested.emit("s")
	# Le classement FINAL fait foi : c'est la regle qui le produit, pas
	# l'accumulation des rangs vus en direct. Les rangs live servent l'affichage
	# pendant la course ; ils sont reconcilies ici.
	var final_order := _rule.final_ranking(_race_state)
	for position: int in range(final_order.size()):
		_race_state.rank[final_order[position]] = position + 1
	_result = RaceResult.from_state(_race_state, _rule, reason)
	_result.interrupted = _interrupted or _is_safety_cap(reason)
	_result.interruption_note = _interruption_note
	if _is_safety_cap(reason) and _result.interruption_note.is_empty():
		_result.interruption_note = "plafond de sécurité atteint : %s" % _result.end_reason_name()
	_set_state(State.FINISHED)
	race_finished.emit(_result)


func _flag_implausible_peaks() -> void:
	for rider: int in _config.active_riders:
		if _race_state.max_speed_kph[rider] <= Physics.SUSPECT_PEAK_KPH:
			continue
		if _suspect_peaks.has(rider):
			continue
		_suspect_peaks.append(rider)
		speed_implausible.emit(rider, _race_state.max_speed_kph[rider])


func _is_safety_cap(reason: RaceRule.EndReason) -> bool:
	return reason == RaceRule.EndReason.TIME_CAP or reason == RaceRule.EndReason.DISTANCE_CAP


func _set_state(next: State) -> void:
	if _state == next:
		return
	var previous := _state
	_state = next
	state_changed.emit(previous, next)
