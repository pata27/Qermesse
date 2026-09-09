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
var _pickers: Array[ColorPickerButton] = []
var _resets: Array[Button] = []
var _warning: Label


func setup(controller: AppController) -> void:
	_controller = controller
	_build()


func _build() -> void:
	add_child(_heading("Riders"))

	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 12)
	add_child(grid)

	for header: String in ["Piste", "Actif", "Nom", "Dossard", "Couleur", ""]:
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

		# LA COULEUR DE L'ECRAN SUIT LE VELO, pas la charte. Un spectateur qui
		# cherche « le rouge » regarde la salle ; c'est donc au logiciel de
		# s'aligner sur les velos poses sur les rouleaux — docs/04 §2.
		var picker := ColorPickerButton.new()
		picker.color = Color(rider.color)
		picker.custom_minimum_size = Vector2(64, 26)
		picker.edit_alpha = false
		picker.tooltip_text = "Couleur de la piste %d, a faire correspondre au velo" % (lane + 1)
		picker.color_changed.connect(_on_color_changed.bind(lane))
		grid.add_child(picker)
		_pickers.append(picker)

		var reset := Button.new()
		reset.text = "Defaut"
		reset.tooltip_text = "Revenir a la couleur de charte de la piste %d" % (lane + 1)
		reset.pressed.connect(_on_color_reset.bind(lane))
		grid.add_child(reset)
		_resets.append(reset)

	_warning = Label.new()
	# RETOUR A LA LIGNE. Sans lui, l'avertissement dictait la largeur de sa
	# colonne : 571 px pour « Couleurs trop proches sur les pistes 1 et 2 … »,
	# davantage a trois pistes — plus qu'une moitie de fenetre a sa taille
	# minimale. Un texte ne pousse pas les murs ; il se plie.
	_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_warning.custom_minimum_size.x = 480
	_warning.add_theme_color_override("font_color", Color("#FF3B30"))
	add_child(_warning)
	# `refresh()` et non `_refresh_warning()` : le bouton « Defaut » naissait
	# ACTIF sur une piste qui n'avait jamais change de couleur, parce que seul
	# `refresh()` pose son etat. Un bouton qui invite au clic sans rien faire
	# est le meme defaut que STOP sur une course terminee.
	refresh()


## Remet les champs en accord avec le roster.
##
## ON NE REECRIT PAS UN CHAMP DEJA JUSTE. Poser `LineEdit.text` remet le curseur
## en tete, meme quand la valeur posee est celle qui s'y trouve deja. Or chaque
## frappe dans un nom emet `roster_changed`, que le panneau renvoie ici : le
## curseur repartait a zero apres CHAQUE lettre, et l'operateur qui tapait
## « Alice » obtenait « ecilA » — sur l'ecran public, au podium et dans le CSV.
func refresh() -> void:
	for lane: int in range(Protocol.MAX_RIDERS):
		var rider := _controller.roster.rider(lane)
		_checks[lane].set_pressed_no_signal(rider.active)
		if _names[lane].text != rider.name:
			_names[lane].text = rider.name
		if _dossards[lane].text != rider.dossard:
			_dossards[lane].text = rider.dossard
		var color := Color(rider.color)
		if not _pickers[lane].color.is_equal_approx(color):
			_pickers[lane].color = color
		# Le bouton ne sert a rien quand la piste est deja a sa couleur : le
		# griser dit, sans un mot, si elle a ete changee.
		_resets[lane].disabled = rider.color.to_upper() == Roster.DEFAULT_COLORS[lane]
	_refresh_warning()


func active_check(lane: int) -> CheckBox:
	return _checks[lane]


func name_field(lane: int) -> LineEdit:
	return _names[lane]


func color_picker(lane: int) -> ColorPickerButton:
	return _pickers[lane]


func reset_button(lane: int) -> Button:
	return _resets[lane]


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


func _on_color_changed(color: Color, lane: int) -> void:
	# `to_html(false)` : sans alpha. Le roster stocke des « #RRGGBB », et une
	# huitieme paire de chiffres aurait fait echouer la comparaison au defaut.
	_controller.set_rider_color(lane, "#%s" % color.to_html(false).to_upper())
	roster_changed.emit()


func _on_color_reset(lane: int) -> void:
	_controller.reset_rider_color(lane)
	refresh()
	roster_changed.emit()


func _refresh_warning() -> void:
	var lanes := _controller.roster.active_lanes()
	if lanes.is_empty():
		_warning.text = "Aucune piste active : impossible de lancer une course."
	elif _controller.settings.mode == RaceConfig.Mode.PURSUIT and lanes.size() < 2:
		_warning.text = "La poursuite exige au moins deux riders."
	else:
		# SIGNALE, N'INTERDIT PAS — docs/04 §2. Deux velos rouges dans la salle,
		# c'est l'operateur qui a raison contre la charte ; le numero de piste
		# et le nom identifient toujours chacun. Mais un doublon involontaire
		# rend l'ecran ambigu, et cela se dit.
		var clashing := _controller.roster.clashing_lanes()
		_warning.text = "" if clashing.is_empty() else (
			"Couleurs trop proches sur les pistes %s : a l'ecran, elles se confondront."
			% _lane_list(clashing)
		)


## « 1 et 3 » plutot que « [0, 2] » : l'operateur lit des numeros de piste.
static func _lane_list(lanes: Array[int]) -> String:
	var numbers := PackedStringArray()
	for lane: int in lanes:
		numbers.append(str(lane + 1))
	return " et ".join(numbers)


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 20)
	return label
