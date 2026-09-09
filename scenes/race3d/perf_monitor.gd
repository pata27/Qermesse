## Surveillance du budget de rendu — docs/04 §4.
##
## « 60 fps stables en 1080p sur un GPU intégré. Toute fonctionnalité visuelle
## qui fait passer sous 60 fps est coupée ou dégradée. » Ce fichier applique la
## règle plutôt que de l'espérer.
##
## `RefCounted` sans dépendance à la scène : la décision de dégrader se teste
## sans écran.
class_name PerfMonitor
extends RefCounted

const TARGET_FPS := 60.0
## On ne dégrade pas sur un hoquet : il faut une fenêtre entière sous le budget.
const WINDOW_S := 3.0
## Marge : à 57 fps on ne dégrade pas encore, la mesure elle-même est bruitée.
const TRIGGER_FPS := 55.0

## FENETRE GLISSANTE. Le moniteur gardait TOUTES les images depuis le
## lancement : un flottant par image, toute la soiree, sur la machine reelle
## d'un evenement — et deux compteurs qu'il n'a jamais relus. Il ne garde que
## les dernieres `retain_s` secondes : de quoi juger « stables », pas de quoi
## grossir. L'outil de mesure regle cette fenetre sur la sienne.
var retain_s := 60.0
var _clock_s := 0.0
var _below_since_s := 0.0
var _samples: Array[float] = []
var _stamps: Array[float] = []


func reset() -> void:
	_clock_s = 0.0
	_below_since_s = 0.0
	_samples.clear()
	_stamps.clear()


## Rend true quand le budget n'est pas tenu assez longtemps pour qu'il faille
## dégrader. L'appelant décide quoi faire — ce module ne touche à rien.
func sample(delta_s: float, fps: float) -> bool:
	_clock_s += delta_s
	_samples.append(fps)
	_stamps.append(_clock_s)
	while not _stamps.is_empty() and _clock_s - _stamps[0] > retain_s:
		_stamps.pop_front()
		_samples.pop_front()

	if fps < TRIGGER_FPS:
		_below_since_s += delta_s
	else:
		_below_since_s = 0.0

	if _below_since_s >= WINDOW_S:
		_below_since_s = 0.0
		return true
	return false


func average_fps() -> float:
	if _samples.is_empty():
		return 0.0
	var total := 0.0
	for value: float in _samples:
		total += value
	return total / float(_samples.size())


## Le pire centile compte plus que la moyenne : une moyenne à 62 fps avec des
## chutes à 30 se voit à l'écran, pas dans le chiffre.
##
## Le fps fourni doit être déduit du temps de CHAQUE image. Un compteur lissé
## par le moteur, rafraîchi une fois par seconde, produirait une série de
## valeurs répétées sur laquelle un centile n'a aucun sens.
func percentile_fps(ratio: float) -> float:
	if _samples.is_empty():
		return 0.0
	var sorted := _samples.duplicate()
	sorted.sort()
	var index := clampi(int(float(sorted.size() - 1) * ratio), 0, sorted.size() - 1)
	return sorted[index]


func min_fps() -> float:
	return percentile_fps(0.0)


func sample_count() -> int:
	return _samples.size()


func budget_met() -> bool:
	# Le budget est tenu si le premier centile reste au-dessus du seuil : c'est
	# la définition de « stables ».
	return percentile_fps(0.01) >= TRIGGER_FPS


func report() -> String:
	# LA CIBLE EST DITE, pas seulement le verdict. `TARGET_FPS` portait le
	# budget de `docs/04` §4 et n'etait lu par rien : le rapport jugeait contre
	# `TRIGGER_FPS`, la marge de bruit, sans jamais nommer les 60 fps qu'on
	# vise. Un « NON TENU » sans reperes ne dit pas de combien on est loin.
	return (
		(
			"%d images — moyenne %.1f fps, 1%% bas %.1f, minimum %.1f"
			+ " — cible %.0f fps, seuil %.0f — budget %s"
		)
		% [
			_samples.size(),
			average_fps(),
			percentile_fps(0.01),
			min_fps(),
			TARGET_FPS,
			TRIGGER_FPS,
			"TENU" if budget_met() else "NON TENU",
		]
	)
