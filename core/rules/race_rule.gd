## Interface commune des trois regles de course — docs/02.
##
## Une regle LIT l'etat et rend un verdict. Elle ne mute rien : c'est le moteur
## qui applique. Sans cette separation, departager trois modes deviendrait un
## enchevetrement de cas particuliers — le defaut exact de la v1.
class_name RaceRule
extends RefCounted

enum EndReason {
	NONE = 0,
	ALL_FINISHED,  ## tous les riders actifs ont franchi la ligne
	TIME_ELAPSED,  ## la duree demandee est ecoulee
	LAST_ONE_STANDING,  ## poursuite : il ne reste qu'un rider
	TIME_CAP,  ## plafond de securite en duree
	DISTANCE_CAP,  ## plafond de securite en distance
}


class Verdict:
	extends RefCounted
	var race_over: bool = false
	var reason: EndReason = EndReason.NONE
	## [{rider, elapsed_ms}] — riders ayant franchi la ligne sur cette trame.
	var newly_finished: Array[Dictionary] = []
	## [{rider, gap_m}] — riders elimines sur cette trame (poursuite).
	var newly_eliminated: Array[Dictionary] = []

	func has_events() -> bool:
		return race_over or not newly_finished.is_empty() or not newly_eliminated.is_empty()


func rule_name() -> String:
	return "abstraite"


## Appelee une fois au depart.
func begin(_state: RaceState) -> void:
	pass


## Appelee a chaque trame retenue. Ne doit RIEN modifier dans `state`.
func evaluate(_state: RaceState) -> Verdict:
	return Verdict.new()


## Classement final, du premier au dernier. Appelee une fois la course finie.
## Le boitier signale qu'un coureur a franchi la ligne (trame `<idx>F:`).
##
## Ce n'est PAS une condition de fin — le firmware ignore quelles pistes sont
## actives — mais c'est une observation de capteur, et une regle peut choisir de
## s'en servir. Rend `true` si l'etat a ete corrige et merite une reevaluation.
func note_hardware_finish(_state: RaceState, _rider: int) -> bool:
	return false


func final_ranking(_state: RaceState) -> Array[int]:
	return []
