## Panneau mode de course — D, T, G et politique de faux depart (docs/02).
##
## Les bornes affichees sont celles de la spec, appliquees par les widgets :
## une valeur hors bornes ne doit pas pouvoir etre saisie, plutot qu'etre
## refusee au moment du depart.
class_name PanelMode
extends VBoxContainer

signal mode_changed()

var _controller: AppController
var _mode_button: OptionButton
var _distance: SpinBox
var _duration: SpinBox
var _gap: SpinBox
var _time_cap: SpinBox
var _distance_cap: SpinBox
var _policy: OptionButton
var _penalty: SpinBox
var _rows: Dictionary = {}


func setup(controller: AppController) -> void:
	_controller = controller
	_build()
	refresh()


func _build() -> void:
	var title := Label.new()
	title.text = "Mode de course"
	title.add_theme_font_size_override("font_size", 20)
	add_child(title)

	_mode_button = OptionButton.new()
	_mode_button.add_item("Distance", RaceConfig.Mode.DISTANCE)
	_mode_button.add_item("Temps", RaceConfig.Mode.TIME)
	_mode_button.add_item("Poursuite", RaceConfig.Mode.PURSUIT)
	_mode_button.item_selected.connect(_on_mode_selected)
	add_child(_mode_button)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	add_child(grid)

	_distance = _spin(grid, "distance", "Distance (m)", 50.0, 5000.0, 10.0)
	_duration = _spin(grid, "duration", "Durée (s)", 10.0, 3600.0, 5.0)
	_gap = _spin(grid, "gap", "Écart décisif (m)", 10.0, 500.0, 5.0)
	# docs/02 §3 : les deux plafonds qui empechent une poursuite infinie. Ce
	# sont les seuls a le faire — ils se reglent ici, pas dans un fichier.
	_time_cap = _spin(grid, "time_cap", "Plafond de durée (s)", 10.0, 3600.0, 10.0)
	_distance_cap = _spin(grid, "distance_cap", "Plafond de distance (m)", 100.0, 100000.0, 100.0)

	var policy_label := Label.new()
	policy_label.text = "Faux départ"
	grid.add_child(policy_label)
	_policy = OptionButton.new()
	_policy.add_item("Ignorer", RaceConfig.FalseStartPolicy.IGNORE)
	_policy.add_item("Avertissement", RaceConfig.FalseStartPolicy.WARN)
	_policy.add_item("Relance", RaceConfig.FalseStartPolicy.RESTART)
	_policy.add_item("Pénalité", RaceConfig.FalseStartPolicy.PENALTY)
	_policy.item_selected.connect(_on_policy_selected)
	grid.add_child(_policy)

	_penalty = _spin(grid, "penalty", "Pénalité (m)", 0.0, 500.0, 1.0)


func refresh() -> void:
	var settings := _controller.settings
	_mode_button.select(_mode_button.get_item_index(int(settings.mode)))
	_distance.set_value_no_signal(settings.distance_m)
	_duration.set_value_no_signal(settings.duration_s)
	_gap.set_value_no_signal(settings.gap_m)
	_time_cap.set_value_no_signal(settings.pursuit_time_cap_s)
	_distance_cap.set_value_no_signal(settings.pursuit_distance_cap_m)
	_policy.select(_policy.get_item_index(int(settings.false_start_policy)))
	_penalty.set_value_no_signal(settings.false_start_penalty_m)

	# Seuls les parametres du mode choisi sont montres : un ecran qui affiche
	# trois reglages dont deux sans effet invite a se tromper de champ.
	_set_row_visible("distance", settings.mode == RaceConfig.Mode.DISTANCE)
	_set_row_visible("duration", settings.mode == RaceConfig.Mode.TIME)
	_set_row_visible("gap", settings.mode == RaceConfig.Mode.PURSUIT)
	_set_row_visible("time_cap", settings.mode == RaceConfig.Mode.PURSUIT)
	_set_row_visible("distance_cap", settings.mode == RaceConfig.Mode.PURSUIT)
	_set_row_visible(
		"penalty", settings.false_start_policy == RaceConfig.FalseStartPolicy.PENALTY
	)


func mode_selector() -> OptionButton:
	return _mode_button


func distance_field() -> SpinBox:
	return _distance


func gap_field() -> SpinBox:
	return _gap


func time_cap_field() -> SpinBox:
	return _time_cap


func distance_cap_field() -> SpinBox:
	return _distance_cap


func penalty_field() -> SpinBox:
	return _penalty


func policy_selector() -> OptionButton:
	return _policy


func _spin(
	grid: GridContainer, key: String, text: String, low: float, high: float, step: float
) -> SpinBox:
	var label := Label.new()
	label.text = text
	grid.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.step = step
	spin.value_changed.connect(_on_value_changed.bind(key))
	grid.add_child(spin)
	_rows[key] = [label, spin]
	return spin


func _set_row_visible(key: String, visible_row: bool) -> void:
	for node: Control in _rows[key]:
		node.visible = visible_row


func _on_mode_selected(index: int) -> void:
	_controller.settings.mode = _mode_button.get_item_id(index) as RaceConfig.Mode
	refresh()
	mode_changed.emit()


func _on_policy_selected(index: int) -> void:
	_controller.settings.false_start_policy = (
		_policy.get_item_id(index) as RaceConfig.FalseStartPolicy
	)
	refresh()
	mode_changed.emit()


func _on_value_changed(value: float, key: String) -> void:
	match key:
		"distance":
			_controller.settings.distance_m = value
		"duration":
			_controller.settings.duration_s = value
		"gap":
			_controller.settings.gap_m = value
		"time_cap":
			_controller.settings.pursuit_time_cap_s = value
		"distance_cap":
			_controller.settings.pursuit_distance_cap_m = value
		"penalty":
			_controller.settings.false_start_penalty_m = value
	mode_changed.emit()
