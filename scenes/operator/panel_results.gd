## Ecran de resultats et historique de la journee — docs/05 lot 3.
class_name PanelResults
extends VBoxContainer

var _controller: AppController
var _table: RichTextLabel
var _history: ItemList
var _export_button: Button
var _csv_label: Label


func setup(controller: AppController) -> void:
	_controller = controller
	_build()
	# Les courses deja sur disque aujourd'hui — le logiciel a pu etre relance.
	for result: RaceResult in _controller.history():
		_add_history_item(result)
	_controller.race_finished.connect(_on_race_finished)


func _build() -> void:
	var title := Label.new()
	title.text = "Resultats"
	title.add_theme_font_size_override("font_size", 20)
	add_child(title)

	_table = RichTextLabel.new()
	_table.bbcode_enabled = false
	_table.custom_minimum_size = Vector2(520, 140)
	_table.text = "Aucune course terminee."
	add_child(_table)

	var history_title := Label.new()
	history_title.text = "Courses du jour"
	add_child(history_title)

	_history = ItemList.new()
	_history.custom_minimum_size = Vector2(520, 110)
	_history.item_selected.connect(_on_history_selected)
	add_child(_history)

	_export_button = Button.new()
	_export_button.text = "Ouvrir le dossier du CSV"
	_export_button.pressed.connect(_on_export)
	add_child(_export_button)

	_csv_label = Label.new()
	_csv_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_csv_label.custom_minimum_size.x = 520
	add_child(_csv_label)


func table_text() -> String:
	return _table.text


func history_count() -> int:
	return _history.item_count


func csv_path_label() -> String:
	return _csv_label.text


func show_result(result: RaceResult) -> void:
	var lines: Array[String] = []
	lines.append(
		"%s — %s%s"
		% [
			result.mode,
			result.end_reason_name(),
			"  [INTERROMPUE : %s]" % result.interruption_note if result.interrupted else "",
		]
	)
	lines.append("rang  piste  nom            distance   temps       moy      max")
	for rider: int in result.ranking:
		# MEME LECTURE QUE LE PODIUM SPECTACLE. Le temps est le temps COURU :
		# l'arrivee pour un classe, l'elimination — marquee — pour un elimine.
		# Imprimer `finished_ms` pour tout le monde donnait 0,00 s a un elimine,
		# sans dire ni quand ni pourquoi, alors que l'ecran public disait juste.
		var timing := "    —    "
		if result.finished_ms[rider] > 0:
			timing = "%6.2f s  " % (result.finished_ms[rider] / 1000.0)
		elif result.eliminated[rider] and result.eliminated_ms[rider] > 0:
			timing = "%6.2f s x" % (result.eliminated_ms[rider] / 1000.0)
		elif result.eliminated[rider]:
			timing = " elimine "
		lines.append(
			"%4d  %5d  %-14s %7.1f m  %s  %5.1f  %5.1f"
			% [
				result.rank_of(rider),
				rider + 1,
				result.rider_name(rider),
				result.distance_m[rider],
				timing,
				result.avg_kph[rider],
				result.max_kph[rider],
			]
		)
	if result.mode == "poursuite":
		lines.append("x = elimine a cet instant ; distance et moyenne arretees la")
	_table.text = "\n".join(lines)
	# Le chemin du CSV est affiche en clair : un operateur doit pouvoir le
	# retrouver sans deviner ou le logiciel range ses fichiers.
	_csv_label.text = "CSV : %s" % _controller.recorder.csv_path()


## Selectionne une course de l'historique, comme un clic dans la liste.
func select_history(index: int) -> void:
	_history.select(index)
	_on_history_selected(index)


func _add_history_item(result: RaceResult) -> void:
	_history.add_item(
		"%s  %s  vainqueur %s (piste %d)"
		% [result.finished_at_iso, result.mode, result.rider_name(result.winner()), result.winner() + 1]
	)


func _on_race_finished(result: RaceResult) -> void:
	show_result(result)
	_add_history_item(result)


func _on_history_selected(index: int) -> void:
	var results := _controller.history()
	if index >= 0 and index < results.size():
		show_result(results[index])


func _on_export() -> void:
	var path := _controller.recorder.csv_path()
	if path.is_empty():
		_csv_label.text = "Aucun CSV ecrit pour l'instant."
		return
	OS.shell_open(path.get_base_dir())
