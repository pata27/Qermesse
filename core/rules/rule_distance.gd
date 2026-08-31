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

var _target_ticks: int = 0


func rule_name() -> String:
	return "distance"


func begin(state: RaceState) -> void:
	_target_ticks = state.physics.metres_to_ticks(state.config.distance_m)


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
		# Ex aequo au tick pres : departage par l'ordre d'arrivee de la trame,
		# ce que l'ordre stable de `active_riders` preserve. Documente comme
		# « photo-finish » dans l'interface (docs/02 §1).
		return state.finished_ms[a] < state.finished_ms[b])
	unfinished.sort_custom(func(a: int, b: int) -> bool:
		return state.distance_m[a] > state.distance_m[b])

	var ranking: Array[int] = []
	ranking.append_array(finished)
	ranking.append_array(unfinished)
	return ranking


func target_ticks() -> int:
	return _target_ticks
