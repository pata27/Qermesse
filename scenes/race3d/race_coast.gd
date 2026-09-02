## ROUE LIBRE ET REGROUPEMENT — ce que les coureurs font APRÈS la ligne.
##
## Sorti de `race_scene.gd`, à onze lignes de la limite du linter. La frontière
## est nette : ce fichier ne fait que des mathématiques sur des positions
## d'affichage, sans rien connaître de la 3D — donc il se teste seul, ce que la
## version enfouie dans la scène ne permettait pas. Le regroupement n'était
## jusqu'ici vérifié que par une capture.
##
## `RaceState.apply_sample` cesse volontairement de mettre à jour un coureur qui
## a franchi la ligne : son résultat est acquis, et le laisser bouger le
## fausserait. Conséquence à l'écran : il se FIGEAIT net sur la ligne, à pleine
## vitesse, pendant que les autres continuaient — le contraire de ce qu'on
## vient de regarder.
##
## L'avance ajoutée ici est un effet d'AFFICHAGE et rien d'autre : elle ne
## remonte jamais vers le moteur, ne touche ni aux distances mesurées, ni aux
## temps, ni au classement. L'habillage continue d'afficher la donnée du
## boîtier ; c'est la scène 3D, et elle seule, qui laisse rouler.
class_name RaceCoast
extends RefCounted

## Constante de temps de la décélération après la ligne.
const TAU_S := 1.5
## Un coureur arrivé ne s'arrête pas : il décélère vers une vitesse de
## croisière — un tiers de sa vitesse de passage, jamais moins qu'une allure de
## promenade — et la garde sous la célébration et le podium. Une roue libre qui
## tombait à zéro en trois secondes se lisait comme un arrêt net, et le sol
## cessait de défiler sous la caméra de fin. Les éliminés, eux, s'arrêtent :
## ils sont sortis de la course.
const CRUISE_FRACTION := 0.35
const MIN_CRUISE_M_S := 2.5
## REGROUPEMENT. Une fois tout le monde arrivé, les suivants accélèrent pour
## revenir se placer derrière le premier, dans l'ordre d'arrivée, à quelques
## mètres — jamais devant lui : une contrainte de position le garantit. La
## caméra retrouve tout le monde dans un seul cadre pour la célébration, et la
## scission se referme d'elle-même en les voyant se rapprocher.
const REGROUP_SPACING_M := 2.5
const REGROUP_MIN_SPACING_M := 1.5
const REGROUP_GAIN := 1.2
const REGROUP_EXTRA_M_S := 16.0

var _speed: Dictionary = {}
var _cruise: Dictionary = {}
var _extra: Dictionary = {}


## Une nouvelle course repart de zéro. Jamais remise, la roue libre reprenait à
## la course suivante la vitesse résiduelle de la précédente — nulle — et
## ajoutait d'un coup au passage de la ligne les mètres accumulés la fois
## d'avant : un arrêt sec et un saut, à chaque course sauf la première.
func reset() -> void:
	_speed.clear()
	_cruise.clear()
	_extra.clear()


## Fait rouler les arrivés et les éliminés. `positions` est modifié en place ;
## `lanes` énumère les couloirs affichés.
##
## CONTRAT : `positions` porte les positions MESURÉES de cette image — celles
## que rendent les interpolateurs —, jamais la sortie de l'appel précédent.
## L'avance de roue libre est gardée à part et rajoutée à chaque fois : passer
## le résultat précédent la compterait deux fois, et le coureur partirait à
## l'infini. Un rider arrivé ne bouge plus côté moteur, sa position mesurée est
## donc constante — c'est bien ce qui rend le calcul stable.
func advance(delta: float, state: RaceState, positions: Dictionary, lanes: Array) -> void:
	if state == null:
		return
	# Les arrivés dans l'ORDRE D'ARRIVÉE : chacun se règle sur celui qui le
	# précède, dont la position de cette image est déjà connue.
	var finished: Array[int] = []
	var everyone_done := true
	for lane: int in lanes:
		if state.finished_ms[lane] > 0:
			finished.append(lane)
		elif not state.eliminated[lane]:
			everyone_done = false
	finished.sort_custom(
		func(a: int, b: int) -> bool: return state.finished_ms[a] < state.finished_ms[b]
	)

	var order: Array[int] = finished.duplicate()
	for lane: int in lanes:
		if state.eliminated[lane] and state.finished_ms[lane] == 0:
			order.append(lane)

	var ahead := -1
	for lane: int in order:
		if not _speed.has(lane):
			# Vitesse au moment du franchissement : c'est de là que part la
			# décélération.
			_speed[lane] = state.display_speed_kph[lane] / 3.6
			_cruise[lane] = (
				0.0 if state.eliminated[lane]
				else maxf(float(_speed[lane]) * CRUISE_FRACTION, MIN_CRUISE_M_S)
			)
		var cruise: float = float(_cruise[lane])
		var base := float(positions[lane])
		var shown := base + float(_extra.get(lane, 0.0))
		var target := cruise
		if everyone_done and ahead >= 0 and state.finished_ms[lane] > 0:
			# Revenir se placer derrière celui de devant, en accélérant — sans
			# jamais le rattraper.
			var wanted := float(positions[ahead]) - REGROUP_SPACING_M
			var error := wanted - shown
			target = float(_speed[ahead]) + clampf(error * REGROUP_GAIN, -1.0, REGROUP_EXTRA_M_S)
			target = maxf(target, 0.0)
		var speed: float = target + (float(_speed[lane]) - target) * exp(-delta / TAU_S)
		if speed < 0.25:
			speed = 0.0
		_speed[lane] = speed
		shown += speed * delta
		if ahead >= 0 and state.finished_ms[lane] > 0:
			# L'ordre d'arrivée est une contrainte, pas un souhait.
			shown = minf(shown, float(positions[ahead]) - REGROUP_MIN_SPACING_M)
		_extra[lane] = shown - base
		positions[lane] = shown
		if state.finished_ms[lane] > 0:
			ahead = lane
