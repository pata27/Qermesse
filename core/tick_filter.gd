## Filtre des ticks aberrants — docs/01 §6.3.
##
## Trois motifs de rejet :
##
##   * ticks qui reculent — un compteur cumule ne redescend pas ;
##   * horloge firmware qui recule ;
##   * saut de ticks impossible sur l'intervalle ecoule.
##
## CE QUE CE FILTRE NE PEUT PAS FAIRE, et il faut le dire : rattraper un rebond
## de contact isole. A 100 Hz, un tick vaut 35,9 cm et une trame couvre 10 ms ;
## un seul tick sur cette fenetre implique deja 129 km/h. Le controle de vitesse
## par trame est donc structurellement aveugle a un tick de trop. On tolere
## explicitement UN tick de quantification, et le filtre n'attrape que ce qui est
## reellement attrapable : les sauts massifs, ceux d'une valeur corrompue.
##
## Le vrai garde-fou contre les rebonds est ailleurs : le compteur de rejets et
## le panneau materiel, qui rendent un capteur mal fixe VISIBLE a l'operateur
## avant la course. Pretendre filtrer plus finement donnerait une fausse
## assurance.
##
## Un rejet est TOUJOURS loggue, jamais silencieux : le masquer transformerait
## un probleme mecanique visible en resultat faux.
class_name TickFilter
extends RefCounted

enum Reason {
	NONE = 0,
	SPEED_IMPLAUSIBLE,  ## > 120 km/h : rebond de contact
	TICKS_WENT_BACKWARD,  ## un compteur cumule ne redescend pas
	CLOCK_WENT_BACKWARD,  ## l'horloge firmware a recule : trame douteuse
}

## Un tick de marge, pour absorber la quantification du capteur. Sans elle, le
## premier tick d'une trame de 10 ms serait rejete comme « 129 km/h ». Voir
## l'en-tete de ce fichier.
const QUANTISATION_ALLOWANCE := 1


class Rejection:
	extends RefCounted
	var rider: int
	var reason: Reason
	var previous_ticks: int
	var proposed_ticks: int
	var delta_ms: int
	var implied_kph: float

	func describe() -> String:
		match reason:
			Reason.SPEED_IMPLAUSIBLE:
				return (
					# Numero de piste HUMAIN, 1..4, comme partout a l'ecran.
					"piste %d : %d ticks en %d ms implique %.1f km/h (plafond %.0f)"
					% [
						rider + 1,
						proposed_ticks - previous_ticks,
						delta_ms,
						implied_kph,
						Physics.MAX_PLAUSIBLE_KPH,
					]
				)
			Reason.TICKS_WENT_BACKWARD:
				return (
					"piste %d : ticks cumules en recul, %d -> %d"
					% [rider + 1, previous_ticks, proposed_ticks]
				)
			Reason.CLOCK_WENT_BACKWARD:
				return "horloge firmware en recul de %d ms" % -delta_ms
		return "aucun"

var _physics: Physics
var _accepted_ticks: PackedInt32Array = PackedInt32Array()
var _last_ms: int = -1
var _rejections: Array[Rejection] = []


func _init(physics: Physics) -> void:
	_physics = physics
	_accepted_ticks.resize(Protocol.MAX_RIDERS)
	reset()


func reset() -> void:
	for i: int in range(Protocol.MAX_RIDERS):
		_accepted_ticks[i] = 0
	_last_ms = -1
	_rejections.clear()


## Filtre une trame `R:` complete. Rend les ticks RETENUS pour chaque piste :
## une valeur rejetee est remplacee par la derniere valeur acceptee, jamais par
## une extrapolation. Les valeurs de `R:` etant absolues (docs/01 §3), la trame
## suivante corrigera d'elle-meme.
func accept(ticks: Array, elapsed_ms: int, active_riders: Array) -> PackedInt32Array:
	if _last_ms >= 0 and elapsed_ms < _last_ms:
		var rejection := Rejection.new()
		rejection.rider = -1
		rejection.reason = Reason.CLOCK_WENT_BACKWARD
		rejection.delta_ms = elapsed_ms - _last_ms
		_rejections.append(rejection)
		return _accepted_ticks.duplicate()

	var delta_ms := elapsed_ms - _last_ms if _last_ms >= 0 else elapsed_ms
	for rider: int in active_riders:
		_accept_one(rider, int(ticks[rider]), delta_ms)
	_last_ms = elapsed_ms
	return _accepted_ticks.duplicate()


func _accept_one(rider: int, proposed: int, delta_ms: int) -> void:
	var previous := _accepted_ticks[rider]
	if proposed == previous:
		return
	if proposed < previous:
		_reject(rider, Reason.TICKS_WENT_BACKWARD, previous, proposed, delta_ms, 0.0)
		return
	# La toute premiere trame n'a pas d'intervalle exploitable : on l'accepte.
	if delta_ms <= 0:
		_accepted_ticks[rider] = proposed
		return
	var delta_ticks := proposed - previous
	# Tolerance d'UN tick : sans elle, le premier tick d'une trame de 10 ms
	# serait rejete comme « 129 km/h » alors qu'il ne fait que traduire la
	# quantification du capteur. C'est ce qui a fait tomber onze tests a la
	# premiere execution du lot 2.
	if delta_ticks > _physics.max_plausible_ticks(delta_ms) + QUANTISATION_ALLOWANCE:
		var implied := _physics.speed_kph(delta_ticks, delta_ms)
		_reject(rider, Reason.SPEED_IMPLAUSIBLE, previous, proposed, delta_ms, implied)
		return
	_accepted_ticks[rider] = proposed


func _reject(
	rider: int, reason: Reason, previous: int, proposed: int, delta_ms: int, kph: float
) -> void:
	var rejection := Rejection.new()
	rejection.rider = rider
	rejection.reason = reason
	rejection.previous_ticks = previous
	rejection.proposed_ticks = proposed
	rejection.delta_ms = delta_ms
	rejection.implied_kph = kph
	_rejections.append(rejection)


func rejections() -> Array[Rejection]:
	return _rejections


func rejection_count() -> int:
	return _rejections.size()


func accepted_ticks() -> PackedInt32Array:
	return _accepted_ticks.duplicate()
