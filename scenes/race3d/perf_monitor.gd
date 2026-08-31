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

var _accumulated_s := 0.0
var _frames := 0
var _below_since_s := 0.0
var _samples: Array[float] = []


func reset() -> void:
	_accumulated_s = 0.0
	_frames = 0
	_below_since_s = 0.0
	_samples.clear()


## Rend true quand le budget n'est pas tenu assez longtemps pour qu'il faille
## dégrader. L'appelant décide quoi faire — ce module ne touche à rien.
func sample(delta_s: float, fps: float) -> bool:
	_accumulated_s += delta_s
	_frames += 1
	_samples.append(fps)

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
	return (
		"%d images — moyenne %.1f fps, 1%% bas %.1f, minimum %.1f — budget %s"
		% [
			_samples.size(),
			average_fps(),
			percentile_fps(0.01),
			min_fps(),
			"TENU" if budget_met() else "NON TENU",
		]
	)
