## Socle commun aux tests de l'interface operateur.
##
## Monte un controleur et un panneau ISOLES — ni les reglages de l'utilisateur,
## ni ses donnees — et fournit les gestes de base : attendre le lien, saisir un
## texte, choisir dans une liste, relire le CSV produit.
##
## Sorti de `test_operator_j3.gd`, qui approchait les mille lignes que le linter
## impose. Ce fichier vit hors de `tests/unit` : GUT n'y cherche pas de tests,
## et il n'en contient aucun.
extends GutTest

const TEST_ROOT := "user://test_operateur"

var _controller: AppController
var _panel: OperatorPanel
var _logs: String
var _races: String


func before_each() -> void:
	_logs = ProjectSettings.globalize_path(TEST_ROOT).path_join("logs")
	_races = ProjectSettings.globalize_path(TEST_ROOT).path_join("races")
	_wipe()

	_controller = AppController.new()
	# Coutures de test : ni les reglages de l'utilisateur, ni ses donnees.
	_controller.preferences_enabled = false
	_controller.recorder_logs_dir = _logs
	_controller.recorder_races_dir = _races
	add_child_autofree(_controller)

	_panel = OperatorPanel.new()
	add_child_autofree(_panel)
	_panel.setup(_controller)
	# Le temps du simulateur est accelere : une course de 13 s se deroule en
	# 1,5 s. Rien d'autre n'est modifie.
	_controller.set_simulation_speed(10.0)


func after_all() -> void:
	_wipe()


func _wipe() -> void:
	for dir: String in [_logs, _races]:
		if DirAccess.dir_exists_absolute(dir):
			for name: String in DirAccess.get_files_at(dir):
				DirAccess.remove_absolute(dir.path_join(name))


func _await_identified() -> bool:
	for i: int in range(120):
		await wait_frames(1)
		if _controller.link_state() == Protocol.State.IDENTIFIED:
			return true
	return false


## Saisit un texte comme le ferait un operateur : la valeur ET le signal.
func _type_into(field: LineEdit, text: String) -> void:
	field.text = text
	field.text_changed.emit(text)


func _select_option(button: OptionButton, id: int) -> void:
	var index := button.get_item_index(id)
	button.select(index)
	button.item_selected.emit(index)


func _read_csv_rows() -> Array[PackedStringArray]:
	var path := _controller.recorder.csv_path()
	var rows: Array[PackedStringArray] = []
	if path.is_empty() or not FileAccess.file_exists(path):
		return rows
	var file := FileAccess.open(path, FileAccess.READ)
	while not file.eof_reached():
		var row := file.get_csv_line()
		if row.size() > 1:
			rows.append(row)
	file.close()
	return rows


func _await_running() -> bool:
	for i: int in range(300):
		await wait_frames(1)
		if _controller.engine.state() == RaceEngine.State.RUNNING:
			return true
	return false


func _csv_events() -> Array[String]:
	var events: Array[String] = []
	for row: PackedStringArray in _read_csv_rows():
		events.append(row[1])
	return events
