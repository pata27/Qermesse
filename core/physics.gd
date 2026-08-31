## Conversions physiques — docs/01 §7.
##
## `core/` ne connait ni la scene, ni le port serie, ni le rendu. Ce fichier est
## un `RefCounted` pur : il tourne et se teste en headless.
##
## Toute la calibration du systeme tient dans UN nombre : le diametre du rouleau
## en millimetres, mesure physiquement (distance aimant vers centre, x2). Pas de
## rapport de transmission, pas de developpement — un tick est un tour de
## rouleau, et un tour de rouleau est une circonference.
class_name Physics
extends RefCounted

const DEFAULT_ROLLER_MM := 114.3

## docs/01 §6.3 — au-dela, c'est un rebond de contact, pas un cycliste.
const MAX_PLAUSIBLE_KPH := 120.0

## docs/01 §7 — v1 lissait sur 60 echantillons (~600 ms), trop mou pour un
## rendu de jeu ; v2 sur 10 (~100 ms), trop nerveux. 20 (~200 ms) est le
## compromis retenu, expose en reglage avance.
const SPEED_SAMPLES := 20

## 1 km/h = 1000 m / 3600 s = 0.2777... mm/ms
const KPH_TO_MM_PER_MS := 0.2777777777777778

var roller_mm: float = DEFAULT_ROLLER_MM
var circumference_mm: float = DEFAULT_ROLLER_MM * PI


func _init(roller: float = DEFAULT_ROLLER_MM) -> void:
	set_roller_mm(roller)


func set_roller_mm(value: float) -> void:
	# Un diametre nul ou negatif rendrait toutes les conversions infinies. On
	# retombe sur le defaut plutot que de propager des NaN dans le classement.
	roller_mm = value if value > 0.0 else DEFAULT_ROLLER_MM
	circumference_mm = roller_mm * PI


## Distance parcourue, en metres, pour un nombre de ticks CUMULES.
func ticks_to_metres(ticks: int) -> float:
	return float(ticks) * circumference_mm / 1000.0


## Nombre de ticks a demander au firmware pour une distance donnee.
## Arrondi vers le bas : mieux vaut une course d'un demi-tour trop courte que
## d'un demi-tour trop longue, l'ecart etant sous la precision du capteur.
func metres_to_ticks(metres: float) -> int:
	if metres <= 0.0:
		return 0
	return int(floor(metres * 1000.0 / circumference_mm))


## Vitesse instantanee, en km/h, entre deux trames.
func speed_kph(delta_ticks: int, delta_ms: int) -> float:
	if delta_ms <= 0 or delta_ticks <= 0:
		return 0.0
	var mm_per_ms := float(delta_ticks) * circumference_mm / float(delta_ms)
	return mm_per_ms / KPH_TO_MM_PER_MS


## Ticks maximum plausibles sur un intervalle donne — sert au filtre de
## docs/01 §6.3. Au-dela, la trame implique une vitesse impossible.
func max_plausible_ticks(delta_ms: int) -> int:
	if delta_ms <= 0:
		return 0
	var max_mm := MAX_PLAUSIBLE_KPH * KPH_TO_MM_PER_MS * float(delta_ms)
	return int(ceil(max_mm / circumference_mm))
