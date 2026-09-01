## Rig de caméra — un seul rig, des comportements par mode (docs/04 §4).
##
## Un rig unique plutôt que trois caméras : les transitions entre modes doivent
## être continues, et une coupure franche en pleine course désoriente le public.
class_name CameraRig
extends Node3D

enum Behaviour { PACK, PURSUIT, PHOTO_FINISH, PODIUM }

## Étalement maximal que la caméra tente de cadrer. Au-delà, elle SUIT LE
## LEADER et laisse l'habillage annoncer les écarts.
##
## Sans ce plafond, un écart de 66 m faisait reculer la caméra à 53 mètres : les
## deux coureurs devenaient deux points au milieu d'une piste vide. Cadrer tout
## le monde est impossible passé une certaine distance — c'est la règle de toute
## retransmission, et il vaut mieux l'assumer que la subir.

## Vue 3/4 arrière légèrement surélevée — la composition de docs/04 §4.
##
## Bien plus proche que la première version : à sept mètres et demi, un vélo
## occupait quarante pixels et se lisait comme une tache. Corrigé après retour
## de l'utilisateur (`tasks/lessons.md`).
const BASE_OFFSET := Vector3(1.9, 1.75, -3.9)
const BASE_FOV := 52.0
const MAX_FRAMED_SPREAD_M := 13.0
## Le dutch angle ne dépasse jamais ce seuil : au-delà, l'horizon penché
## devient un effet de style qui nuit à la lecture des positions.
const MAX_DUTCH_RAD := 0.055
## Vibration de la caméra à pleine allure, en radians — environ trois pixels en
## 1080p. Au-delà, cela cesse d'être une caméra tenue le long d'une piste pour
## devenir un défaut d'image.
const MAX_VIBRATION_RAD := 0.0026
## Vitesse à partir de laquelle la caméra commence à vibrer, et celle à laquelle
## la vibration est pleine.
const VIBRATION_FROM_KPH := 20.0
const VIBRATION_FULL_KPH := 52.0
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
## Décadrage horizontal, en radians. Sert à l'écran scindé : chaque sujet doit
## se placer DANS SA MOITIÉ d'image, sinon la vue du poursuivant recouvre
## purement et simplement le leader.
var _frame_shift := 0.0
var _frame_fraction := 1.0
var _dutch_now := 0.0
var _snap_pending := false
var _vibe_clock := 0.0


func _ready() -> void:
	camera = Camera3D.new()
	camera.name = "Camera3D"
	camera.fov = BASE_FOV
	# Le tampon de profondeur est distribué de façon logarithmique : un plan
	# proche à dix centimètres consomme presque toute la précision sur le
	# premier mètre et n'en laisse plus pour le fond, qui se met à papilloter.
	# La caméra ne s'approche jamais à moins d'un mètre d'un coureur.
	camera.near = 0.5
	camera.far = 900.0
	add_child(camera)
	camera.position = BASE_OFFSET
	camera.look_at_from_position(BASE_OFFSET, Vector3.ZERO, Vector3.UP)


## `focus_x` : abscisse du sujet — son couloir. La caméra vise SON couloir, pas
## le milieu de la piste : sans cela le décadrage de l'écran scindé partait
## d'une base inconnue et le sujet sortait du champ.
## `focus_z` : position du sujet le long de la piste.
## `spread_z` : étalement entre le premier et le dernier, en mètres.
## `speed_kph` : vitesse du leader, qui pilote FOV et dutch angle.
func aim(focus_x: float, focus_z: float, spread_z: float, lateral_span: float,
		speed_kph: float) -> void:
	var speed_ratio := clampf(speed_kph / 60.0, 0.0, 1.2)
	# Au-delà du plafond, la caméra cesse de reculer et suit le leader.
	var framed := minf(absf(spread_z), MAX_FRAMED_SPREAD_M)

	match behaviour:
		Behaviour.PACK:
			# Cadrer tout le peloton : la caméra recule juste assez pour que le
			# dernier reste dans le champ.
			# Composition : les coureurs occupent le tiers central, l'horizon
			# reste haut, et le bas du cadre n'est pas deux tiers de bois vide.
			# La caméra est CENTRÉE — un décalage latéral marqué faisait
			# ressortir un relevé sur toute la moitié de l'écran.
			# Vue 3/4 ARRIÈRE : plein axe, un vélo se réduit à une tranche et
			# perd sa silhouette. Le décalage latéral est ce qui donne le volume.
			var back := 3.9 + framed * 0.75 + speed_ratio * 1.4
			# Volet étroit : reculer d'autant plus que la part d'écran est
			# petite. Pas la proportion entière — un recul strictement inverse
			# à la largeur éloignerait tellement la caméra que le groupe
			# deviendrait illisible ; un tiers de la correction suffit à le
			# ramener dans son volet.
			back *= 1.0 + (1.0 / _frame_fraction - 1.0) * 0.34
			var height := 1.75 + framed * 0.07 + speed_ratio * 0.45
			# L'épaule se prend PAR RAPPORT AU SUJET, pas au milieu de la piste.
			#
			# La caméra se plaçait à une abscisse fixe déduite de la largeur de
			# piste, et ne faisait que pivoter vers `focus_x`. Un leader dans le
			# couloir de droite était donc vu de biais et se retrouvait presque
			# au centre de l'image — collé à la lame de séparation au lieu
			# d'occuper son demi-cadre.
			_target_position = Vector3(
				focus_x + lateral_span * 0.34 + 1.15, height, focus_z - back
			)
			# Vise plus haut et plus loin : plonger vers le sol remplissait le
			# tiers inférieur du cadre de bois vide.
			_target_look = Vector3(focus_x, 1.45, focus_z - framed * 0.4 + 3.0)
			# docs/04 §4 : léger dutch angle à haute vitesse.
			_dutch = -MAX_DUTCH_RAD * speed_ratio
			# Le champ s'ouvre avec la vitesse ET se creuse à l'accélération :
			# c'est le second terme qui fait sentir la relance.
			# Le gain sur l'accélération peut être plus franc depuis qu'elle est
			# longuement lissée : ce qui rendait le champ instable était le
			# bruit du signal, pas son amplitude.
			_target_fov = BASE_FOV + speed_ratio * 9.0 + clampf(_accel, -6.0, 10.0) * 1.4

		Behaviour.PURSUIT:
			# Cadrer l'ÉCART : elle recule et s'élève quand il se creuse, se
			# resserre quand ça se recolle. C'est l'écart qui est le sujet.
			# Même plafond : l'écart est le sujet, mais un écart de cinquante
			# mètres ne se cadre pas — c'est l'habillage qui le chiffre.
			var gap := framed
			var back := 5.0 + gap * 1.05
			var height := 1.8 + gap * 0.30
			_target_position = Vector3(lateral_span * 0.35 + 1.8, height, focus_z - back)
			_target_look = Vector3(0.0, 1.0, focus_z - gap * 0.5)
			_dutch = -MAX_DUTCH_RAD * 0.5 * speed_ratio
			_target_fov = BASE_FOV + clampf(gap * 0.25, 0.0, 12.0)

		Behaviour.PHOTO_FINISH:
			# Plan latéral sur la ligne — le moment qui fait crier une salle.
			_target_position = Vector3(lateral_span * 0.5 + 6.5, 1.15, focus_z + 0.4)
			_target_look = Vector3(focus_x, 1.0, focus_z)
			_dutch = 0.0
			_target_fov = 38.0

		Behaviour.PODIUM:
			_target_position = Vector3(focus_x, 2.2, focus_z - 6.0)
			_target_look = Vector3(focus_x, 1.4, focus_z)
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
	# Lissee LONGUEMENT : la derivee d'un signal deja quantifie est extremement
	# bruitee, et cette derivee pilote le champ de la camera. Lissee trop
	# faiblement, elle faisait battre le champ image par image — le scintillement
	# que l'utilisateur a decrit. Une seconde de constante de temps ne coute rien
	# a la sensation de relance, qui dure plusieurs secondes.
	_accel = lerpf(_accel, instant, clampf(delta * 1.1, 0.0, 1.0))


func acceleration() -> float:
	return _accel


func target_position() -> Vector3:
	return _target_position


## Place la caméra SUR sa cible, sans interpolation. Indispensable quand une
## vue apparaît : sans cela, la seconde caméra de l'écran scindé entrait en
## volant depuis l'origine du monde et montrait le sol de très près pendant une
## bonne seconde.
## Décadrage voulu, en FRACTION DE LARGEUR D'ÉCRAN (−0,5 à +0,5). La conversion
## en angle se fait ici parce qu'elle dépend du champ, et que le champ s'ouvre
## avec la vitesse : une constante calculée ailleurs se trompait d'autant plus
## que la course allait vite.
func set_frame_shift(screen_fraction: float) -> void:
	_frame_shift = screen_fraction


## Part de la largeur d'écran dont dispose cette vue, entre 0 et 1. Un volet qui
## ne dispose que du quart de l'image ne peut pas cadrer son groupe depuis la
## même distance qu'un plein écran : sans ce recul, les coureurs les plus
## excentrés du groupe sortaient du volet.
func set_frame_fraction(fraction: float) -> void:
	_frame_fraction = clampf(fraction, 0.2, 1.0)


## Angle de décadrage correspondant à la fraction d'écran demandée, pour le
## champ courant. `Camera3D.fov` est le champ VERTICAL : le champ horizontal
## s'en déduit par le rapport d'image.
func _shift_angle() -> float:
	if is_zero_approx(_frame_shift):
		return 0.0
	var view := camera.get_viewport()
	var aspect := 16.0 / 9.0
	if view != null:
		var size := view.get_visible_rect().size
		if size.y > 0.0:
			aspect = size.x / size.y
	var half_h := atan(tan(deg_to_rad(camera.fov) * 0.5) * aspect)
	return atan(2.0 * _frame_shift * tan(half_h))


## Demande un placement immédiat à la PROCHAINE image. À utiliser quand une vue
## apparaît : sans cela, la caméra d'un volet qui s'ouvre entre en volant depuis
## l'origine du monde et montre le sol de très près pendant une bonne seconde.
## Une seule image — ensuite l'amortissement reprend.
func request_snap() -> void:
	_snap_pending = true


func snap() -> void:
	camera.position = _target_position
	camera.fov = _target_fov
	_dutch_now = _dutch
	camera.look_at(_target_look, Vector3.UP)
	camera.rotate_object_local(Vector3.UP, _shift_angle())
	camera.rotate_object_local(Vector3.FORWARD, _dutch_now)


func advance(delta: float) -> void:
	if _snap_pending:
		_snap_pending = false
		snap()
		return

	# Amortissement indépendant du framerate : la caméra doit se comporter
	# pareil à 60 et à 144 images par seconde.
	var alpha := 1.0 - exp(-delta * 3.2)
	camera.position = camera.position.lerp(_target_position, alpha)
	# LE CHAMP ET LE ROULIS SE CALENT PLUS LENTEMENT QUE LA POSITION.
	#
	# Tous deux dérivent de la vitesse, qui arrive par ticks : à 45 km/h un tick
	# tombe toutes les 29 ms, et la mesure saute d'un tick à l'autre. Suivre ce
	# signal au rythme de la position faisait respirer le cadre et rouler
	# l'horizon à chaque image. Ce sont des effets de fond : ils ont le droit
	# d'être en retard, ils n'ont pas le droit de trembler.
	var slow := 1.0 - exp(-delta * 1.4)
	camera.fov = lerpf(camera.fov, _target_fov, slow)
	_dutch_now = lerpf(_dutch_now, _dutch, slow)

	var look := _target_look
	if _shake > 0.001:
		var amount := _shake * 0.06
		look += Vector3(randf_range(-amount, amount), randf_range(-amount, amount), 0.0)
		_shake = maxf(0.0, _shake - delta * 2.5)

	camera.look_at(look, Vector3.UP)
	camera.rotate_object_local(Vector3.UP, _shift_angle())
	camera.rotate_object_local(Vector3.FORWARD, _dutch_now)
	_apply_vibration(delta)


## Micro-vibration de la caméra, d'autant plus marquée que ça va vite.
##
## DÉTERMINISTE — somme de sinusoïdes, jamais `randf`. Le tremblement qu'il a
## fallu supprimer venait du BRUIT d'un signal mesuré : il changeait de sens à
## chaque image et se lisait comme un défaut. Une oscillation à fréquence fixe
## se lit au contraire comme une caméra tenue le long d'une piste, et rend la
## sensation d'allure que l'amortissement avait emportée avec le bruit.
##
## Les trois fréquences sont premières entre elles : leur somme ne se répète
## qu'au bout de plusieurs secondes, sans quoi l'oreille de l'oeil entendrait
## le motif.
func _apply_vibration(delta: float) -> void:
	_vibe_clock += delta
	var reach := VIBRATION_FULL_KPH - VIBRATION_FROM_KPH
	var force := clampf((_last_speed_kph - VIBRATION_FROM_KPH) / reach, 0.0, 1.0)
	if force <= 0.0:
		return
	var amp := force * force * MAX_VIBRATION_RAD
	var pitch := sin(_vibe_clock * 23.3) * amp + sin(_vibe_clock * 37.7) * amp * 0.45
	var yaw := sin(_vibe_clock * 29.1) * amp * 0.7
	camera.rotate_object_local(Vector3.RIGHT, pitch)
	camera.rotate_object_local(Vector3.UP, yaw)


func set_behaviour_for_mode(mode: RaceConfig.Mode) -> void:
	behaviour = Behaviour.PURSUIT if mode == RaceConfig.Mode.PURSUIT else Behaviour.PACK
