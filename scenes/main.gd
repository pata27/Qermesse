## Racine de l'application — docs/03 §2, « routeur ».
##
## Se contente d'instancier le controleur et la fenetre operateur. Le mode
## degrade mono-fenetre est le defaut ; la fenetre spectacle arrive au lot 5.
extends Node

var controller: AppController
var operator: OperatorPanel


func _ready() -> void:
	controller = AppController.new()
	controller.name = "AppController"
	add_child(controller)

	operator = OperatorPanel.new()
	operator.name = "OperatorPanel"
	add_child(operator)
	operator.setup(controller)

	get_window().title = "SilverSprint v3 — operateur"
	get_window().min_size = Vector2i(1100, 760)


func _notification(what: int) -> void:
	# Les noms des riders et les reglages sont persistes a la fermeture : la v1
	# les perdait a chaque lancement (docs/02 §5).
	if what == NOTIFICATION_WM_CLOSE_REQUEST and controller != null:
		controller.save_preferences()
