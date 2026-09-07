## VITRINE — ce que l'écran montre quand personne ne pédale.
##
## Une borne d'arcade ne reste jamais noire entre deux joueurs : elle rejoue une
## partie toute seule, et c'est cette partie-là qui donne envie de mettre une
## pièce. Un goldsprint a le même problème — entre deux manches, le projecteur
## affiche un podium figé ou rien, et la file se dissout.
##
## **Ce n'est pas une animation, ce sont de VRAIES courses.** Le simulateur
## produit les mêmes trames que le boîtier, le moteur les arbitre, l'écran les
## rend. La vitrine ne fait que choisir les scénarios et enchaîner. Une
## animation séparée aurait été un second logiciel à maintenir, qui aurait
## dérivé du premier — et qui aurait montré autre chose que le produit.
##
## **Rien de ce qui s'y passe n'a eu lieu.** `AppController.demo_mode` rend le
## `Recorder` muet, tient la course hors de « Courses du jour » et empêche la
## sauvegarde des réglages. Une vitrine qui laisserait des traces rendrait la
## soirée de l'opérateur illisible, et un doute sur ce qui a réellement été
## couru est un doute sur tout le fichier.
##
## **Elle rend tout ce qu'elle a emprunté.** Mode, distance, durée, écart,
## plafonds, profil du simulateur, pistes actives, backend : tout est repris à
## l'arrêt, exactement comme l'opérateur l'avait laissé. Il lance la vitrine
## pendant l'apéritif et clique START quand les coureurs arrivent.
class_name AttractMode
extends Node

## Émis quand la vitrine démarre ou s'arrête, pour que le panneau suive.
signal changed()

## Ce que la vitrine sait montrer. L'ordre compte : on ouvre sur un
## photo-finish à deux — la course la plus lisible, celle qui se comprend sans
## explication — et on garde la poursuite à quatre, la plus spectaculaire, pour
## quand le passant s'est arrêté.
const SCENARIOS := [
	{
		"mode": RaceConfig.Mode.DISTANCE,
		"riders": 2,
		"profile": "egaux",
		"distance_m": 250.0,
	},
	{
		"mode": RaceConfig.Mode.PURSUIT,
		"riders": 4,
		"profile": "domination",
		"gap_m": 35.0,
	},
	{
		"mode": RaceConfig.Mode.TIME,
		"riders": 3,
		"profile": "remontee-finale",
		"duration_s": 30.0,
	},
	{
		"mode": RaceConfig.Mode.DISTANCE,
		"riders": 4,
		"profile": "casse-par-etapes",
		"distance_m": 500.0,
	},
]

## Repos entre deux manches, le temps que le podium se lise.
const BREATH_S := 6.0
## Délai d'un enchaînement bloqué. Si le lien ne répond pas ou qu'une course
## reste coincée, on repart sur le scénario suivant plutôt que de figer l'écran
## — une vitrine gelée est pire qu'une vitrine absente.
const STUCK_S := 90.0

## LA VITRINE TOURNE EN TEMPS RÉEL. Elle a d'abord accéléré le simulateur trois
## fois, sur l'idée qu'une démonstration n'a pas à durer ce que dure une course
## — et c'était une faute. Un passant doit voir une course CRÉDIBLE ; des
## coureurs qui pédalent en accéléré et un décompte qui défile se lisent comme
## un défaut, pas comme un résumé. Une manche de 250 m dure vingt secondes, et
## c'est très bien : c'est le temps qu'il faut pour s'arrêter et regarder.
##
## Couture de test, uniquement : la suite ne peut pas attendre trois manches
## réelles.
var speed_scale := 1.0

var _controller: AppController
var _root: Node
var _running := false
var _index := 0
var _wait_s := 0.0
var _elapsed_s := 0.0
var _saved: Dictionary = {}


func setup(controller: AppController, root: Node) -> void:
	_controller = controller
	_root = root
	_controller.race_finished.connect(_on_race_over.unbind(1))
	_controller.race_aborted.connect(_on_race_over.unbind(1))


func is_running() -> bool:
	return _running


## Démarre la vitrine. Rend false si une vraie course est en cours : on
## n'interrompt jamais des gens qui pédalent pour lancer une démonstration.
func start() -> bool:
	if _running:
		return true
	if _controller.race_in_progress():
		_controller.notice.emit("mode démo : impossible pendant une course")
		return false
	_remember()
	_running = true
	_index = 0
	_wait_s = 0.0
	_elapsed_s = 0.0
	_controller.demo_mode = true
	# LE SIMULATEUR, TOUJOURS. Un vrai boîtier branché recevrait le `g` de
	# départ et attendrait des ticks que personne ne produit : la vitrine
	# afficherait quatre pistes muettes, puis l'alerte « aucun tick depuis le
	# départ ». Le backend est rendu à l'arrêt.
	_controller.apply_backend(true)
	_controller.set_simulation_speed(speed_scale)
	_apply_cinematic(1.0)
	_next_race()
	changed.emit()
	return true


## Arrête la vitrine et REND tout ce qu'elle avait emprunté.
func stop() -> void:
	if not _running:
		return
	_running = false
	# La course en cours est une course de démonstration : elle s'arrête là où
	# elle en est, et personne n'a besoin de son classement.
	if _controller.race_in_progress():
		_controller.engine.abort("fin du mode démo")
	_apply_cinematic(0.0)
	_restore()
	_controller.demo_mode = false
	changed.emit()


func _process(delta: float) -> void:
	if not _running:
		return
	_elapsed_s += delta
	if _wait_s > 0.0:
		_wait_s -= delta
		if _wait_s <= 0.0:
			_next_race()
		return
	# GARDE-FOU. Une manche qui ne se termine pas — lien muet, moteur bloqué —
	# figerait la vitrine sur une image morte, ce qui est pire que pas de
	# vitrine du tout. On passe à la suivante.
	if _elapsed_s > STUCK_S:
		_next_race()


## Enchaîne sur le scénario suivant.
func _next_race() -> void:
	if not _running:
		return
	_elapsed_s = 0.0
	var scenario: Dictionary = SCENARIOS[_index % SCENARIOS.size()]
	_index += 1
	_apply(scenario)
	if not _controller.start_race(true):
		# Le lien n'est pas encore identifié au tout premier passage : on
		# réessaie au tour suivant plutôt que d'abandonner la vitrine.
		_wait_s = 1.0


func _apply(scenario: Dictionary) -> void:
	var settings := _controller.settings
	settings.mode = scenario["mode"]
	if scenario.has("distance_m"):
		settings.distance_m = float(scenario["distance_m"])
	if scenario.has("duration_s"):
		settings.duration_s = float(scenario["duration_s"])
	if scenario.has("gap_m"):
		settings.gap_m = float(scenario["gap_m"])
	var riders := int(scenario["riders"])
	for lane: int in range(Protocol.MAX_RIDERS):
		_controller.roster.set_active(lane, lane < riders)
	# LE SIMULATEUR DOIT AVOIR ASSEZ DE CAPTEURS CABLES. Sans cela, une manche
	# à quatre coureurs en montrerait deux qui roulent et deux à l'arrêt —
	# exactement l'image qu'une vitrine ne doit pas donner.
	_controller.set_simulator_riders(riders)
	_controller.set_simulator_profile(str(scenario["profile"]))


## Fin de manche, normale ou interrompue : on respire, puis on enchaîne.
func _on_race_over() -> void:
	if not _running:
		return
	_wait_s = BREATH_S


func _apply_cinematic(amount: float) -> void:
	if _root == null:
		return
	var spectacle: Variant = _root.get("spectacle")
	if spectacle == null:
		return
	var scene: Variant = spectacle.get("scene")
	if scene != null:
		(scene as RaceScene).set_cinematic(amount)


## Met de côté ce que la vitrine va écraser.
##
## TOUT CE QU'ELLE TOUCHE, sans exception. Un réglage oublié ici, c'est une
## configuration silencieusement changée sous les pieds de l'opérateur, qui
## lancera sa vraie course suivante sur la distance de la démonstration.
func _remember() -> void:
	var settings := _controller.settings
	var lanes: Array[bool] = []
	for lane: int in range(Protocol.MAX_RIDERS):
		lanes.append(_controller.roster.rider(lane).active)
	_saved = {
		"mode": settings.mode,
		"distance_m": settings.distance_m,
		"duration_s": settings.duration_s,
		"gap_m": settings.gap_m,
		"lanes": lanes,
		"simulated": _controller.is_simulated(),
		"profile": _controller.simulator_profile(),
		"simulator_riders": _controller.simulator_riders(),
		"speed": _controller.simulation_speed(),
	}


func _restore() -> void:
	if _saved.is_empty():
		return
	var settings := _controller.settings
	settings.mode = _saved["mode"]
	settings.distance_m = float(_saved["distance_m"])
	settings.duration_s = float(_saved["duration_s"])
	settings.gap_m = float(_saved["gap_m"])
	var lanes: Array = _saved["lanes"]
	for lane: int in range(Protocol.MAX_RIDERS):
		_controller.roster.set_active(lane, bool(lanes[lane]))
	_controller.set_simulator_riders(int(_saved["simulator_riders"]))
	_controller.set_simulator_profile(str(_saved["profile"]))
	# CE QU'IL Y AVAIT, pas une valeur par defaut. Remettre 1,0 en dur ecrasait
	# une acceleration que l'operateur — ou un outil — avait posee lui-meme.
	_controller.set_simulation_speed(float(_saved["speed"]))
	# EN DERNIER. Rebasculer sur le matériel referme le simulateur : les
	# réglages qu'on vient de lui rendre doivent être posés AVANT, sinon ils
	# tombent dans le vide et l'opérateur retrouve un simulateur par défaut le
	# jour où il y revient.
	_controller.apply_backend(bool(_saved["simulated"]))
	_saved = {}
