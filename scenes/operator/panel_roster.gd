## Panneau roster — 1 a 4 riders, noms, dossards, couleurs, activation de piste.
##
## docs/03 §6 : un rider est identifie par sa couleur ET son numero de piste.
## Aucune information ne repose sur la seule couleur.
class_name PanelRoster
extends VBoxContainer

signal roster_changed()

var _controller: AppController
var _checks: Array[CheckBox] = []
var _names: Array[LineEdit] = []
var _dossards: Array[LineEdit] = []
var _warning: Label


func setup(controller: AppController) -> void:
	_controller = controller
	_build()


func _build() -> void:
	add_child(_heading("Riders"))

	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 12)
	add_child(grid)

	for header: String in ["Piste", "Actif", "Nom", "Dossard", ""]:
		var label := Label.new()
		label.text = header
		grid.add_child(label)

	for lane: int in range(Protocol.MAX_RIDERS):
		var rider := _controller.roster.rider(lane)

		var lane_label := Label.new()
		# Le numero de piste est affiche en clair : c'est lui qui identifie le
		# rider quand la couleur n'est pas distinguable (videoprojecteur pale,
		# daltonisme).
		lane_label.text = "Piste %d" % (lane + 1)
		grid.add_child(lane_label)

		var check := CheckBox.new()
		check.button_pressed = rider.active
		check.toggled.connect(_on_active_toggled.bind(lane))
		grid.add_child(check)
		_checks.append(check)

		var name_edit := LineEdit.new()
		name_edit.text = rider.name
		name_edit.placeholder_text = "Piste %d" % (lane + 1)
		# La saisie s'arrete a ce que l'ecran public peut montrer : mieux vaut
		# un champ qui refuse une lettre qu'un nom coupe a la surprise generale.
		name_edit.max_length = Roster.MAX_DISPLAY_NAME
		name_edit.custom_minimum_size.x = 180
		name_edit.text_changed.connect(_on_name_changed.bind(lane))
		grid.add_child(name_edit)
		_names.append(name_edit)

		var dossard_edit := LineEdit.new()
		dossard_edit.text = rider.dossard
		dossard_edit.max_length = Roster.MAX_DOSSARD
		dossard_edit.custom_minimum_size.x = 70
		dossard_edit.text_changed.connect(_on_dossard_changed.bind(lane))
		grid.add_child(dossard_edit)
		_dossards.append(dossard_edit)

		var swatch := ColorRect.new()
		swatch.color = Color(rider.color)
		swatch.custom_minimum_size = Vector2(24, 24)
		grid.add_child(swatch)

	_warning = Label.new()
	_warning.add_theme_color_override("font_color", Color("#FF3B30"))
	add_child(_warning)
	_refresh_warning()


func refresh() -> void:
	for lane: int in range(Protocol.MAX_RIDERS):
		var rider := _controller.roster.rider(lane)
		_checks[lane].set_pressed_no_signal(rider.active)
		_names[lane].text = rider.name
		_dossards[lane].text = rider.dossard
	_refresh_warning()


func active_check(lane: int) -> CheckBox:
	return _checks[lane]


func name_field(lane: int) -> LineEdit:
	return _names[lane]


func warning_text() -> String:
	return _warning.text


func _on_active_toggled(pressed: bool, lane: int) -> void:
	_controller.roster.set_active(lane, pressed)
	_refresh_warning()
	roster_changed.emit()


func _on_name_changed(text: String, lane: int) -> void:
	_controller.roster.rider(lane).name = text
	roster_changed.emit()


func _on_dossard_changed(text: String, lane: int) -> void:
	_controller.roster.rider(lane).dossard = text
	roster_changed.emit()


func _refresh_warning() -> void:
	var lanes := _controller.roster.active_lanes()
	if lanes.is_empty():
		_warning.text = "Aucune piste active : impossible de lancer une course."
	elif _controller.settings.mode == RaceConfig.Mode.PURSUIT and lanes.size() < 2:
		_warning.text = "La poursuite exige au moins deux riders."
	else:
		_warning.text = ""


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 20)
	return label
