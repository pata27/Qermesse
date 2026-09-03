## Etat instantane d'une course — la vue que les regles arbitrent.
##
## Ne contient AUCUNE logique de decision : les regles lisent, le moteur ecrit.
## Un objet d'etat qui deciderait quelque chose rendrait les trois modes
## impossibles a departager.
class_name RaceState
extends RefCounted

## Fenêtre longue réservée à l'AFFICHAGE. À 47 km/h un tick tombe toutes les
## 27 ms : sur 200 ms on en compte 7 ou 8, soit 12 % d'écart, et le chiffre
## sautait visiblement entre 41 et 47 sans que le cycliste change d'allure.
## Une seconde de moyenne ramène la quantification sous 2 %.
const DISPLAY_WINDOW_SAMPLES := 100

var physics: Physics
var config: RaceConfig

## docs/01 §3 — horloge FIRMWARE, seule horloge de course. L'horloge du PC ne
## sert qu'aux delais d'attente et a l'interpolation du rendu.
var elapsed_ms: int = 0

var ticks: PackedInt32Array = PackedInt32Array()
var distance_m: PackedFloat32Array = PackedFloat32Array()
var speed_kph: PackedFloat32Array = PackedFloat32Array()
## Vitesse destinée à l'ÉCRAN : plus lissée, donc stable à lire. Le pilotage de
## la caméra et des effets continue d'utiliser `speed_kph`, plus réactive.
var display_speed_kph: PackedFloat32Array = PackedFloat32Array()
var max_speed_kph: PackedFloat32Array = PackedFloat32Array()

## 0 = pas encore arrive. L'instant du franchissement, en ms firmware.
var finished_ms: PackedInt32Array = PackedInt32Array()
## Instant de l'elimination, en ms depuis le depart ; 0 tant que le rider court.
## Sans lui, la moyenne d'un elimine se calculait sur TOUTE la course alors que
## sa distance est figee a l'elimination : elle etait fausse, toujours trop
## basse, et le podium ne pouvait pas dire quand il avait saute.
var eliminated_ms: PackedInt32Array = PackedInt32Array()
## Rang final, 1 = vainqueur. 0 = pas encore classe.
var rank: PackedInt32Array = PackedInt32Array()
var eliminated: Array[bool] = []
## docs/02 §4, politique PENALITE : handicap de depart, en metres.
var handicap_m: PackedFloat32Array = PackedFloat32Array()
var false_started: Array[bool] = []

var _smoothers: Array[SpeedSmoother] = []
var _display_smoothers: Array[SpeedSmoother] = []
var _previous_ticks: PackedInt32Array = PackedInt32Array()
var _previous_ms: int = -1


func _init(race_config: RaceConfig) -> void:
	config = race_config
	physics = Physics.new(race_config.roller_mm)
	var n := Protocol.MAX_RIDERS
	ticks.resize(n)
	distance_m.resize(n)
	speed_kph.resize(n)
	display_speed_kph.resize(n)
	max_speed_kph.resize(n)
	finished_ms.resize(n)
	eliminated_ms.resize(n)
	rank.resize(n)
	handicap_m.resize(n)
	_previous_ticks.resize(n)
	for i: int in range(n):
		eliminated.append(false)
		false_started.append(false)
		_smoothers.append(SpeedSmoother.new())
		_display_smoothers.append(SpeedSmoother.new(DISPLAY_WINDOW_SAMPLES))
	reset()


func reset() -> void:
	for i: int in range(Protocol.MAX_RIDERS):
		ticks[i] = 0
		distance_m[i] = 0.0
		speed_kph[i] = 0.0
		display_speed_kph[i] = 0.0
		max_speed_kph[i] = 0.0
		finished_ms[i] = 0
		eliminated_ms[i] = 0
		rank[i] = 0
		handicap_m[i] = 0.0
		eliminated[i] = false
		false_started[i] = false
		_previous_ticks[i] = 0
		_smoothers[i].reset()
		_display_smoothers[i].reset()
	elapsed_ms = 0
	_previous_ms = -1


## Applique une trame de ticks DEJA filtree. Les valeurs sont absolues :
## on ecrase, on n'accumule jamais (docs/01 §3).
func apply_sample(accepted_ticks: PackedInt32Array, sample_ms: int) -> void:
	var delta_ms := sample_ms - _previous_ms if _previous_ms >= 0 else 0
	elapsed_ms = sample_ms
	for rider: int in config.active_riders:
		var value := accepted_ticks[rider]
		# Un rider arrive ou elimine est FIGE : sa distance ne bouge plus, meme
		# s'il continue de pedaler. docs/02 §1, « fige a son franchissement ».
		if finished_ms[rider] != 0 or eliminated[rider]:
			continue
		if delta_ms > 0:
			var instant := physics.speed_kph(value - _previous_ticks[rider], delta_ms)
			_smoothers[rider].push(instant)
			speed_kph[rider] = _smoothers[rider].value()
			_display_smoothers[rider].push(instant)
			display_speed_kph[rider] = _display_smoothers[rider].value()
			# La vitesse de POINTE se mesure sur la vitesse lissee, et seulement
			# une fois la fenetre pleine. La vitesse instantanee ne veut rien
			# dire a cette echelle : un tick vaut 35,9 cm et une trame 10 ms,
			# si bien qu'un seul tick affiche 129 km/h. Un cycliste a 45 km/h
			# sortait ainsi avec une « pointe » a 117 km/h dans le CSV.
			if _smoothers[rider].is_full():
				max_speed_kph[rider] = maxf(max_speed_kph[rider], speed_kph[rider])
		ticks[rider] = value
		distance_m[rider] = physics.ticks_to_metres(value) + handicap_m[rider]
		_previous_ticks[rider] = value
	_previous_ms = sample_ms


func is_racing(rider: int) -> bool:
	return (
		config.active_riders.has(rider)
		and finished_ms[rider] == 0
		and not eliminated[rider]
	)


## Riders encore en course : actifs, ni arrives, ni elimines.
func racing_riders() -> Array[int]:
	var out: Array[int] = []
	for rider: int in config.active_riders:
		if is_racing(rider):
			out.append(rider)
	return out


## Rider le plus avance parmi ceux encore en course. -1 si aucun.
## Les couloirs donnes, classes par distance parcourue — LE PLUS AVANCE
## D'ABORD, la piste departageant une egalite.
##
## Ce tri etait recopie a l'identique dans la regle de distance, celle de
## poursuite et l'habillage, et aucun n'avait de departage. `sort_custom` n'est
## pas stable : a distance egale, la regle et l'ecran pouvaient designer des
## meneurs DIFFERENTS — au plafond de securite, c'est le vainqueur qui change.
func by_distance(lanes: Array) -> Array[int]:
	var out: Array[int] = []
	for lane: Variant in lanes:
		out.append(int(lane))
	out.sort_custom(func(a: int, b: int) -> bool:
		if not is_equal_approx(distance_m[a], distance_m[b]):
			return distance_m[a] > distance_m[b]
		return a < b)
	return out


## MEME REGLE QUE `by_distance` : a distance egale, le couloir le plus petit
## l'emporte — la comparaison stricte garde le premier vu, et `racing_riders`
## rend les couloirs dans l'ordre. Les deux doivent rester d'accord : le
## meneur affiche a l'ecran est celui que le classement met en tete.
func leader() -> int:
	var best := -1
	for rider: int in racing_riders():
		if best < 0 or distance_m[rider] > distance_m[best]:
			best = rider
	return best


## Rider le moins avance parmi ceux encore en course. -1 si aucun.
func trailer() -> int:
	var worst := -1
	for rider: int in racing_riders():
		if worst < 0 or distance_m[rider] < distance_m[worst]:
			worst = rider
	return worst


## Ecart en metres entre le premier et le dernier des riders encore en course.
func spread_m() -> float:
	var first := leader()
	var last := trailer()
	if first < 0 or last < 0:
		return 0.0
	return distance_m[first] - distance_m[last]


## Rang a attribuer au prochain rider qui FRANCHIT la ligne : un de plus que le
## nombre d'arrives. Ne compte pas les elimines, qui sont classes par le bas.
func next_finish_rank() -> int:
	var arrived := 0
	for rider: int in config.active_riders:
		if finished_ms[rider] != 0:
			arrived += 1
	return arrived + 1


## Rang a attribuer au prochain ELIMINE : la derniere place encore libre, soit
## le nombre de riders pas encore classes. docs/02 §3, « riders restants + 1 ».
func next_elimination_rank() -> int:
	var unranked := 0
	for rider: int in config.active_riders:
		if rank[rider] == 0:
			unranked += 1
	return unranked
