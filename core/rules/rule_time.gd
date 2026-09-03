## Mode TEMPS — docs/02 §2.
##
## Distance maximale parcourue en T secondes. La condition de fin est calculee
## **par le PC seul** : le firmware deborde son int 16 bits sur
## `raceLengthSecs * 1000` et ne termine jamais une course de plus de
## 32 secondes (docs/01 §5.5). La « double detection » n'a jamais existe.
class_name RuleTime
extends RaceRule

var _limit_ms: int = 0


func rule_name() -> String:
	return "temps"


func begin(state: RaceState) -> void:
	_limit_ms = int(state.config.duration_s * 1000.0)


func evaluate(state: RaceState) -> Verdict:
	var verdict := Verdict.new()
	if state.elapsed_ms < _limit_ms:
		return verdict

	verdict.race_over = true
	verdict.reason = EndReason.TIME_ELAPSED
	# Tout le monde « arrive » a l'instant du gong : c'est la distance qui
	# departage, pas le temps.
	for rider: int in state.config.active_riders:
		if state.finished_ms[rider] == 0:
			verdict.newly_finished.append({"rider": rider, "elapsed_ms": state.elapsed_ms})
	return verdict


## Decroissant par ticks cumules. Ex aequo departage par vitesse de pointe —
## et si elle est egale aussi, par numero de piste.
##
## docs/02 §2 s'arretait a la pointe. `sort_custom` n'etant pas stable, deux
## coureurs identiques — cas courant au simulateur, possible en vrai — se
## classaient dans un ordre qui pouvait changer d'une execution a l'autre.
## Arbitraire mais deterministe vaut mieux qu'arbitraire tout court.
func final_ranking(state: RaceState) -> Array[int]:
	var ranking: Array[int] = state.config.active_riders.duplicate()
	ranking.sort_custom(func(a: int, b: int) -> bool:
		if state.ticks[a] != state.ticks[b]:
			return state.ticks[a] > state.ticks[b]
		if not is_equal_approx(state.max_speed_kph[a], state.max_speed_kph[b]):
			return state.max_speed_kph[a] > state.max_speed_kph[b]
		return a < b)
	return ranking


