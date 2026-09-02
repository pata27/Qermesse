## Mode POURSUITE — docs/02 §3.
##
## La course dure tant qu'aucun rider n'a pris un ecart decisif. Le firmware
## n'en sait rien et n'en saura jamais rien : c'est le PC, exclusivement, qui
## decide, et qui envoie `s` quand il a decide.
##
## Regle a 2 riders : fin des que |d0 - d1| >= G.
##
## Regle a 3-4 riders : ELIMINATION PROGRESSIVE (tranchee avec l'utilisateur).
## Des que l'ecart entre le leader et le dernier rider encore en course atteint
## G, ce dernier est elimine avec le rang « nombre de riders restants + 1 ». On
## continue jusqu'a ce qu'il n'en reste qu'un.
##
## La variante « premier a mettre G a TOUS les autres » reste implementable
## derriere cette meme interface ; elle n'est pas ecrite tant qu'elle n'est pas
## demandee, pour ne pas laisser de code mort (docs/06 §1).
class_name RulePursuit
extends RaceRule

var _gap_m: float = 50.0
## Ordre d'elimination, du premier sorti au dernier. Sert au classement final.
var _elimination_order: Array[int] = []


func rule_name() -> String:
	return "poursuite"


func begin(state: RaceState) -> void:
	_gap_m = state.config.gap_m
	_elimination_order.clear()


func evaluate(state: RaceState) -> Verdict:
	var verdict := Verdict.new()
	var racing := state.racing_riders()

	# Il ne reste qu'un rider : la poursuite est finie.
	if racing.size() <= 1:
		verdict.race_over = true
		verdict.reason = EndReason.LAST_ONE_STANDING
		return verdict

	var cap := _safety_cap(state)
	if cap != EndReason.NONE:
		# docs/02 §3 — sans ces plafonds, deux riders de niveau egal courent
		# jusqu'a epuisement. Inacceptable en evenementiel.
		verdict.race_over = true
		verdict.reason = cap
		return verdict

	var leader := state.leader()
	var trailer := state.trailer()
	if leader < 0 or trailer < 0 or leader == trailer:
		return verdict

	var gap := state.distance_m[leader] - state.distance_m[trailer]
	if gap < _gap_m:
		return verdict

	# L'ecart decisif est atteint. Le dernier sort.
	verdict.newly_eliminated.append({"rider": trailer, "gap_m": gap})
	if racing.size() == 2:
		# A deux riders, eliminer le dernier revient a terminer la course : le
		# leader gagne. On le marque arrive pour qu'il ait un temps de reference.
		verdict.newly_finished.append({"rider": leader, "elapsed_ms": state.elapsed_ms})
		verdict.race_over = true
		verdict.reason = EndReason.LAST_ONE_STANDING
	return verdict


func note_elimination(rider: int) -> void:
	if not _elimination_order.has(rider):
		_elimination_order.append(rider)


## Ce qui reste avant que le plafond de duree tranche — docs/02 §3 exige que
## ce soit visible a l'ecran.
static func seconds_before_decision(state: RaceState) -> float:
	return maxf(0.0, state.config.pursuit_time_cap_s - state.elapsed_ms / 1000.0)


## Idem pour le plafond de distance, mesure sur le leader.
static func metres_before_decision(state: RaceState) -> float:
	var leader := state.leader()
	var lead_m := state.distance_m[leader] if leader >= 0 else 0.0
	return maxf(0.0, state.config.pursuit_distance_cap_m - lead_m)


## Le plafond qui tranchera en premier, en proportion de son etendue, et lui
## seul : deux compteurs a rebours cote a cote ne se lisent pas.
static func decision_text(state: RaceState) -> String:
	var seconds := seconds_before_decision(state)
	var metres := metres_before_decision(state)
	var time_share := seconds / maxf(1.0, state.config.pursuit_time_cap_s)
	var distance_share := metres / maxf(1.0, state.config.pursuit_distance_cap_m)
	if distance_share < time_share:
		return "decision a %.0f m" % metres
	return "decision dans %d:%02d" % [int(seconds) / 60, int(seconds) % 60]


func _safety_cap(state: RaceState) -> EndReason:
	if state.elapsed_ms >= int(state.config.pursuit_time_cap_s * 1000.0):
		return EndReason.TIME_CAP
	var leader := state.leader()
	if leader >= 0 and state.distance_m[leader] >= state.config.pursuit_distance_cap_m:
		return EndReason.DISTANCE_CAP
	return EndReason.NONE


## Le survivant d'abord, puis les elimines dans l'ordre INVERSE de leur sortie :
## le dernier elimine est le mieux classe des sortants.
func final_ranking(state: RaceState) -> Array[int]:
	var ranking: Array[int] = []
	var survivors: Array[int] = []
	for rider: int in state.config.active_riders:
		if not state.eliminated[rider]:
			survivors.append(rider)
	# En cas de plafond de securite, plusieurs survivants : celui qui mene gagne.
	survivors.sort_custom(func(a: int, b: int) -> bool:
		return state.distance_m[a] > state.distance_m[b])
	ranking.append_array(survivors)

	var eliminated := _elimination_order.duplicate()
	eliminated.reverse()
	ranking.append_array(eliminated)
	return ranking


## Progression vers la decision, dans [0, 1]. C'est la valeur que la barre de
## tension et l'intensite audio du lot 5 indexeront.
func tension(state: RaceState) -> float:
	if _gap_m <= 0.0:
		return 0.0
	return clampf(state.spread_m() / _gap_m, 0.0, 1.0)


func gap_threshold_m() -> float:
	return _gap_m


func elimination_order() -> Array[int]:
	return _elimination_order.duplicate()
