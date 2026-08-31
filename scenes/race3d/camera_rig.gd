## Rig de caméra — un seul rig, des comportements par mode (docs/04 §4).
##
## Un rig unique plutôt que trois caméras : les transitions entre modes doivent
## être continues, et une coupure franche en pleine course désoriente le public.
class_name CameraRig
extends Node3D

enum Behaviour { PACK, PURSUIT, PHOTO_FINISH, PODIUM }

## Vue 3/4 arrière légèrement surélevée — la composition de docs/04 §4.
##
## Bien plus proche que la première version : à sept mètres et demi, un vélo
## occupait quarante pixels et se lisait comme une tache. Corrigé après retour
## de l'utilisateur (`tasks/lessons.md`).
const BASE_OFFSET := Vector3(1.9, 1.55, -4.3)
const BASE_FOV := 55.0
## Le dutch angle ne dépasse jamais ce seuil : au-delà, l'horizon penché
## devient un effet de style qui nuit à la lecture des positions.
const MAX_DUTCH_RAD := 0.055
const PHOTO_FINISH_GAP_M := 1.0

var camera: Camera3D
var behaviour: Behaviour = Behaviour.PACK

var _target_position := BASE_OFFSET
var _target_look := Vector3.ZERO
var _target_fov := BASE_FOV
var _dutch := 0.0
var _shake := 0.0
## Vitesse de l'image precedente, pour en deduire l'ACCELERATION. C'est elle qui
## porte la sensation de changement d'allure : a vitesse constante, meme tres
## elevee, l'oeil s'habitue et ne percoit plus rien.
var _last_speed_kph := 0.0
var _accel := 0.0


func _ready() -> void:
	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.fov = BASE_FOV
	camera.near = 0.1
	camera.far = 600.0
	add_child(camera)
	camera.position = BASE_OFFSET
	camera.look_at_from_position(BASE_OFFSET, Vector3.ZERO, Vector3.UP)


## `focus_z` : position du leader dans le repère de la scène.
## `spread_z` : étalement entre le premier et le dernier, en mètres.
## `speed_kph` : vitesse du leader, qui pilote FOV et dutch angle.
func aim(focus_z: float, spread_z: float, lateral_span: float, speed_kph: float) -> void:
	var speed_ratio := clampf(speed_kph / 60.0, 0.0, 1.2)

	match behaviour:
		Behaviour.PACK:
			# Cadrer tout le peloton : la caméra recule juste assez pour que le
			# dernier reste dans le champ.
			var back := 4.3 + spread_z * 0.80 + speed_ratio * 1.6
			var height := 1.55 + spread_z * 0.08 + speed_ratio * 0.55
			_target_position = Vector3(lateral_span * 0.30 + 1.3, height, focus_z - back)
			_target_look = Vector3(0.0, 0.85, focus_z - spread_z * 0.4)
			# docs/04 §4 : léger dutch angle à haute vitesse.
			_dutch = -MAX_DUTCH_RAD * speed_ratio
			# Le champ s'ouvre avec la vitesse ET se creuse à l'accélération :
			# c'est le second terme qui fait sentir la relance.
			_target_fov = BASE_FOV + speed_ratio * 9.0 + clampf(_accel, -6.0, 10.0) * 0.9

		Behaviour.PURSUIT:
			# Cadrer l'ÉCART : elle recule et s'élève quand il se creuse, se
			# resserre quand ça se recolle. C'est l'écart qui est le sujet.
			var gap := absf(spread_z)
			var back := 5.0 + gap * 1.05
			var height := 1.8 + gap * 0.30
			_target_position = Vector3(lateral_span * 0.35 + 1.8, height, focus_z - back)
			_target_look = Vector3(0.0, 1.0, focus_z - gap * 0.5)
			_dutch = -MAX_DUTCH_RAD * 0.5 * speed_ratio
			_target_fov = BASE_FOV + clampf(gap * 0.25, 0.0, 12.0)

		Behaviour.PHOTO_FINISH:
			# Plan latéral sur la ligne — le moment qui fait crier une salle.
			_target_position = Vector3(lateral_span * 0.5 + 6.5, 1.15, focus_z + 0.4)
			_target_look = Vector3(0.0, 1.0, focus_z)
			_dutch = 0.0
			_target_fov = 38.0

		Behaviour.PODIUM:
			_target_position = Vector3(0.0, 2.2, focus_z - 6.0)
			_target_look = Vector3(0.0, 1.4, focus_z)
			_dutch = 0.0
			_target_fov = 48.0


## Décide seule du passage en photo-finish — docs/04 §4 : écart inférieur à 1 m
## à l'approche de la ligne.
func consider_photo_finish(gap_m: float, distance_to_finish_m: float) -> bool:
	var close := gap_m < PHOTO_FINISH_GAP_M and distance_to_finish_m < 12.0
	if close and behaviour != Behaviour.PHOTO_FINISH:
		behaviour = Behaviour.PHOTO_FINISH
		return true
	return false


func punch(strength: float = 1.0) -> void:
	_shake = maxf(_shake, strength)


## Met a jour l'acceleration estimee. Separee de `aim` pour rester lisible :
## une derivee calculee au milieu d'un `match` se remarque mal.
func note_speed(delta: float, speed_kph: float) -> void:
	if delta <= 0.0:
		return
	var instant := (speed_kph - _last_speed_kph) / delta
	_last_speed_kph = speed_kph
	# Lissee : la derivee d'un signal deja quantifie est tres bruitee.
	_accel = lerpf(_accel, instant, clampf(delta * 4.0, 0.0, 1.0))


func acceleration() -> float:
	return _accel


func advance(delta: float) -> void:
	# Amortissement indépendant du framerate : la caméra doit se comporter
	# pareil à 60 et à 144 images par seconde.
	var alpha := 1.0 - exp(-delta * 3.2)
	camera.position = camera.position.lerp(_target_position, alpha)
	camera.fov = lerpf(camera.fov, _target_fov, alpha)

	var look := _target_look
	if _shake > 0.001:
		var amount := _shake * 0.06
		look += Vector3(randf_range(-amount, amount), randf_range(-amount, amount), 0.0)
		_shake = maxf(0.0, _shake - delta * 2.5)

	camera.look_at(look, Vector3.UP)
	camera.rotate_object_local(Vector3.FORWARD, _dutch)


func set_behaviour_for_mode(mode: RaceConfig.Mode) -> void:
	behaviour = Behaviour.PURSUIT if mode == RaceConfig.Mode.PURSUIT else Behaviour.PACK
