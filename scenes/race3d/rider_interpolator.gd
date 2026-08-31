## Interpolation de la position d'un rider entre deux trames — docs/03 §3.
##
## Le problème, chiffré : les trames arrivent à 100 Hz, le rendu tourne à
## 60–144 Hz, et surtout **un tick vaut 35,9 cm**. À 5 km/h, un rider produit un
## tick toutes les ~260 ms, soit un point de donnée toutes les 15 à 37 images.
## Afficher la mesure brute donnerait un escalier parfaitement visible.
##
## `RefCounted` sans dépendance à la scène : testable en headless, y compris le
## cas basse vitesse que `docs/05` exige de vérifier explicitement.
class_name RiderInterpolator
extends RefCounted

## Constante de temps du rattrapage. 80 ms : assez court pour que l'affichage
## colle à la mesure, assez long pour absorber la quantification du capteur.
const TAU_S := 0.08

## L'affichage n'anticipe jamais de plus d'un tick : au-delà, une erreur de
## vitesse deviendrait un rider qui franchit la ligne avant de l'avoir atteinte.
const MAX_LEAD_M := 0.36

var _display_m := 0.0
var _measured_m := 0.0
var _speed_m_s := 0.0
var _age_s := 0.0
var _frozen := false
var _last_display := 0.0


func reset() -> void:
	_display_m = 0.0
	_last_display = 0.0
	_measured_m = 0.0
	_speed_m_s = 0.0
	_age_s = 0.0
	_frozen = false


## Fige l'affichage : rider arrivé ou éliminé. Sa position ne bouge plus, même
## s'il continue de pédaler (docs/02 §1).
func freeze() -> void:
	_frozen = true


func is_frozen() -> bool:
	return _frozen


## Nouvelle mesure. Appelée à la réception d'une trame, pas à chaque image.
func push_sample(distance_m: float, speed_kph: float) -> void:
	if _frozen:
		return
	# Un compteur cumulé ne redescend jamais ; si la valeur recule malgré tout,
	# on garde la précédente plutôt que de faire reculer un vélo à l'écran.
	_measured_m = maxf(_measured_m, distance_m)
	_speed_m_s = maxf(0.0, speed_kph / 3.6)
	_age_s = 0.0


## Position à afficher, en mètres. Appelée à chaque image.
func update(delta_s: float) -> float:
	if _frozen or delta_s <= 0.0:
		return _display_m
	_age_s += delta_s

	# Cible : la dernière mesure, prolongée par la vitesse lissée. C'est cette
	# extrapolation qui remplit les 15 images sans donnée à basse vitesse.
	var target := _measured_m + _speed_m_s * _age_s
	target = minf(target, _measured_m + _speed_m_s * _age_s + MAX_LEAD_M)

	# Rattrapage exponentiel, indépendant du framerate : à 60 comme à 144 Hz,
	# la position converge au même rythme en SECONDES.
	var alpha := 1.0 - exp(-delta_s / TAU_S)
	_display_m += (target - _display_m) * alpha

	# Un vélo ne recule pas à l'écran. Jamais.
	_display_m = maxf(_display_m, _last_display)
	_last_display = _display_m
	return _display_m


func display_m() -> float:
	return _display_m


func measured_m() -> float:
	return _measured_m


func speed_m_s() -> float:
	return _speed_m_s
