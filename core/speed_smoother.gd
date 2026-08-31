## Moyenne mobile de la vitesse affichee — docs/01 §7.
##
## Separe de `physics.gd` parce qu'il porte un ETAT, la : une par rider. La
## conversion, elle, est sans etat et partagee.
class_name SpeedSmoother
extends RefCounted

var _samples: PackedFloat32Array = PackedFloat32Array()
var _capacity: int = Physics.SPEED_SAMPLES
var _cursor: int = 0
var _count: int = 0
var _sum: float = 0.0


func _init(capacity: int = Physics.SPEED_SAMPLES) -> void:
	_capacity = maxi(1, capacity)
	_samples.resize(_capacity)


func push(kph: float) -> void:
	# Tampon circulaire : la somme est maintenue incrementalement, pour ne pas
	# reparcourir la fenetre a chaque trame — 100 fois par seconde, par rider.
	if _count == _capacity:
		_sum -= _samples[_cursor]
	else:
		_count += 1
	_samples[_cursor] = kph
	_sum += kph
	_cursor = (_cursor + 1) % _capacity


func value() -> float:
	return _sum / float(_count) if _count > 0 else 0.0


func reset() -> void:
	_cursor = 0
	_count = 0
	_sum = 0.0
	for i: int in range(_capacity):
		_samples[i] = 0.0


func sample_count() -> int:
	return _count


## Vrai quand la fenetre est pleine. Avant cela, la moyenne porte sur trop peu
## d'echantillons pour valoir comme mesure : un seul tick isole la ferait
## bondir a plus de 100 km/h.
func is_full() -> bool:
	return _count == _capacity
