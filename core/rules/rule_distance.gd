## Mode DISTANCE — docs/02 §1.
##
## Premier rider a parcourir D metres. La course se termine quand **tous les
## riders ACTIFS** ont atteint la cible.
##
## C'est ici que la v1 etait cassee : elle attendait les quatre pistes
## materielles, donc ne se terminait jamais a deux riders. Le firmware, lui,
## continue d'attendre ses quatre pistes — on ne le modifie pas. C'est le PC qui
## conclut, et c'est LUI qui envoie `s`.
class_name RuleDistance
extends RaceRule

## Tolerance, en ticks, sur le retard du compte du PC au moment ou le boitier
## annonce une arrivee. Voir `note_hardware_finish`. Huit ticks valent 2,9 m :
## largement de quoi couvrir une trame `R:` perdue, et bien trop peu pour qu'une
## trame parasite termine une course qui n'en est qu'a la moitie.
const TRAILING_TOLERANCE_TICKS := 8

var _target_ticks: int = 0


func rule_name() -> String:
	return "distance"


func begin(state: RaceState) -> void:
	_target_ticks = state.physics.metres_to_ticks(state.config.distance_m)


## LE DERNIER TICK N'ARRIVE JAMAIS, et ce n'est pas un defaut de l'emulateur.
##
## `ss_basic.ino` (`checkDistanceBased`, l. 285-307) met `raceStarted = false`
## dans la passe meme ou le dernier tick fait franchir la ligne. Or l'emission
## periodique des trames `R:` est conditionnee par `raceStarted`. La valeur qui
## atteint la cible n'est donc JAMAIS transmise : le PC reste bloque un tick en
## dessous, indefiniment, et la course ne se termine pas. Le materiel reel fait
## exactement cela ; l'emulateur le reproduit fidelement, c'est ainsi qu'on l'a
## trouve avant la premiere course.
##
## La regle « les trames R: portent un cumul absolu, donc en perdre une est sans
## consequence » est vraie de toutes les trames SAUF la derniere.
##
## La trame `<idx>F:` est donc lue comme ce qu'elle est : le capteur affirme que
## SON compteur a atteint la valeur que le PC lui a donnee par la commande `l`.
## C'est le critere du PC lui-meme, rapporte par le capteur. On l'accepte, mais
## bornee : si le compte du PC est loin derriere, la trame est incoherente et on
## la refuse plutot que de terminer une course sur une donnee douteuse.
func note_hardware_finish(state: RaceState, rider: int) -> bool:
	if rider < 0 or rider >= state.ticks.size():
		return false
	if state.finished_ms[rider] != 0 or state.eliminated[rider]:
		return false
	if not state.config.active_riders.has(rider):
		return false
	var missing := _target_ticks - state.ticks[rider]
	if missing <= 0 or missing > TRAILING_TOLERANCE_TICKS:
		return false
	state.ticks[rider] = _target_ticks
	state.distance_m[rider] = state.physics.ticks_to_metres(_target_ticks)
	return true


func evaluate(state: RaceState) -> Verdict:
	var verdict := Verdict.new()

	for rider: int in state.config.active_riders:
		if state.finished_ms[rider] != 0:
			continue
		if state.ticks[rider] >= _target_ticks:
			verdict.newly_finished.append({"rider": rider, "elapsed_ms": state.elapsed_ms})

	# Condition de fin : TOUS les riders actifs, et eux seuls.
	var pending := 0
	for rider: int in state.config.active_riders:
		if state.finished_ms[rider] == 0:
			pending += 1
	for entry: Dictionary in verdict.newly_finished:
		if state.finished_ms[int(entry["rider"])] == 0:
			pending -= 1

	if pending <= 0:
		verdict.race_over = true
		verdict.reason = EndReason.ALL_FINISHED
		return verdict

	# docs/02 §1 — plafond de securite : 10 minutes.
	if state.elapsed_ms >= int(state.config.distance_timeout_s * 1000.0):
		verdict.race_over = true
		verdict.reason = EndReason.TIME_CAP
	return verdict


## Croissant par temps de passage. Un rider non arrive est classe apres les
## arrives, par distance decroissante — cas d'une course interrompue au plafond.
func final_ranking(state: RaceState) -> Array[int]:
	var finished: Array[int] = []
	var unfinished: Array[int] = []
	for rider: int in state.config.active_riders:
		if state.finished_ms[rider] != 0:
			finished.append(rider)
		else:
			unfinished.append(rider)

	finished.sort_custom(func(a: int, b: int) -> bool:
		# Ex aequo au tick pres : departage par l'ordre d'arrivee de la trame.
		# Meme trame : rien ne les separe — ranges par numero de piste, et
		# l'interface dit « photo-finish » (docs/02 §1). EXPLICITE : le tri de
		# Godot n'est pas stable, l'ordre de `active_riders` ne garantissait rien.
		if state.finished_ms[a] != state.finished_ms[b]:
			return state.finished_ms[a] < state.finished_ms[b]
		return a < b)
	unfinished = state.by_distance(unfinished)

	var ranking: Array[int] = []
	ranking.append_array(finished)
	ranking.append_array(unfinished)
	return ranking


