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
	# DES LE LANCEMENT, pas apres la premiere course : le manuel fait reperer
	# ce chemin la veille, dans une salle vide.
	_csv_label.text = "CSV : %s" % _controller.recorder.csv_path()
	# Les courses deja sur disque aujourd'hui — le logiciel a pu etre relance.
	_rebuild_history()
	_controller.race_finished.connect(_on_race_finished)
	_controller.demo_mode_changed.connect(_on_demo_mode_changed)
	# Une course arretee entre dans la liste elle aussi : elle a eu lieu, et sa
	# trace est sur le disque.
	_controller.race_aborted.connect(func(_note: String) -> void: _rebuild_history())


func _build() -> void:
	var title := Label.new()
	title.text = "Résultats"
	title.add_theme_font_size_override("font_size", 20)
	add_child(title)

	_table = RichTextLabel.new()
	_table.bbcode_enabled = false
	_table.custom_minimum_size = Vector2(520, 140)
	_table.text = "Aucune course terminée."
	add_child(_table)

	var history_title := Label.new()
	history_title.text = "Courses du jour"
	add_child(history_title)

	_history = ItemList.new()
	_history.custom_minimum_size = Vector2(520, 110)
	_history.item_selected.connect(_on_history_selected)
	add_child(_history)

	_export_button = Button.new()
	_export_button.text = "Ouvrir le dossier des résultats"
	_export_button.pressed.connect(_on_export)
	add_child(_export_button)

	_csv_label = Label.new()
	_csv_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_csv_label.custom_minimum_size.x = 520
	add_child(_csv_label)


func table_text() -> String:
	return _table.text


func history_text(index: int) -> String:
	return "" if index < 0 or index >= _history.item_count else _history.get_item_text(index)


func history_count() -> int:
	return _history.item_count


func csv_path_label() -> String:
	return _csv_label.text


func files_text() -> String:
	return _csv_label.text


func show_result(result: RaceResult) -> void:
	var lines: Array[String] = []
	lines.append(
		"%s — %s%s"
		% [
			result.mode,
			result.end_reason_name(),
			"  [INTERROMPUE : %s]" % result.interruption_note if result.was_stopped() else "",
		]
	)
	# LA COLONNE N'APPARAIT QUE SI ELLE SERT. La plupart des soirees se passent
	# de dossards ; une colonne vide en permanence n'est pas une information,
	# c'est du bruit qui pousse tout le reste vers la droite.
	var numbered := _has_dossards(result)
	lines.append(
		"rang  piste  doss.   nom                distance   temps       moy      max"
		if numbered
		else "rang  piste  nom                distance   temps       moy      max"
	)
	for rider: int in result.ranking:
		# MEME LECTURE QUE LE PODIUM SPECTACLE. Le temps est le temps COURU :
		# l'arrivee pour un classe, l'elimination — marquee — pour un elimine.
		# Imprimer `finished_ms` pour tout le monde donnait 0,00 s a un elimine,
		# sans dire ni quand ni pourquoi, alors que l'ecran public disait juste.
		var timing := "%6.2f s  " % (result.raced_ms(rider) / 1000.0)
		if result.is_dead_heat(rider):
			timing = "%6.2f s =" % (result.raced_ms(rider) / 1000.0)
		if result.finished_ms[rider] == 0 and result.eliminated[rider]:
			timing = (
				"%6.2f s x" % (result.eliminated_ms[rider] / 1000.0)
				if result.eliminated_ms[rider] > 0 else " éliminé "
			)
		elif result.finished_ms[rider] == 0:
			# Survivant d'un plafond ou course interrompue : le temps couru,
			# marque comme tel.
			timing = "%6.2f s *" % (result.raced_ms(rider) / 1000.0)
		# LE DOSSARD DU DEPART, jamais celui du roster courant : renommer ou
		# renumeroter les pistes entre deux manches ne doit pas reetiqueter une
		# course deja courue. C'est la meme regle que les noms, et elle a deja
		# ete enfreinte deux fois sur eux.
		var number := "%-6s  " % result.rider_dossard(rider) if numbered else ""
		lines.append(
			"%4d  %5d  %s%-18s %7.1f m  %s  %5.1f  %5.1f"
			% [
				result.rank_of(rider),
				rider + 1,
				number,
				# Meme borne que l'ecran public : un nom venu d'un fichier
				# ecrit a la main desalignerait sinon toute la ligne.
				result.display_name(rider),
				result.distance_m[rider],
				timing,
				result.avg_kph[rider],
				result.max_kph[rider],
			]
		)
	if result.mode == "poursuite":
		lines.append("x = éliminé à cet instant ; distance et moyenne arrêtées là")
	if result.interrupted:
		lines.append("* = a couru jusqu'à la fin de la course, sans franchir de ligne")
	for rider: int in result.ranking:
		if result.is_dead_heat(rider):
			lines.append("= photo-finish : même trame de passage, rangés par numéro de piste")
			break
	_table.text = "\n".join(lines)
	# Le chemin du CSV est affiche en clair : un operateur doit pouvoir le
	# retrouver sans deviner ou le logiciel range ses fichiers.
	# LES DEUX FICHIERS, pas seulement le journal. Le JSON de la course affichee
	# est celui que le depannage demande d'envoyer au developpeur ; il vivait
	# dans un dossier voisin, sous un nom en uuid que rien n'affichait.
	var lines_files: Array[String] = ["CSV : %s" % _controller.recorder.csv_path()]
	var json := _controller.recorder.json_path(result.uuid)
	if not json.is_empty():
		lines_files.append("Course : %s" % json)
	_csv_label.text = "\n".join(lines_files)


## Une seule piste numerotee suffit a montrer la colonne : si l'operateur a pris
## la peine d'en saisir un, c'est qu'il compte le lire.
static func _has_dossards(result: RaceResult) -> bool:
	for rider: int in result.ranking:
		if not result.rider_dossard(rider).is_empty():
			return true
	return false


## Selectionne une course de l'historique, comme un clic dans la liste.
func select_history(index: int) -> void:
	_history.select(index)
	_on_history_selected(index)


## Reconstruit la liste depuis l'historique du controleur, qui est la seule
## source : ajouter au fil de l'eau laissait diverger ce qu'on voyait pendant
## la soiree et ce qu'on retrouvait apres un redemarrage.
func _rebuild_history() -> void:
	# LE PLUS RECENT EN TETE, comme le journal du panneau Course.
	#
	# La liste se remplissait dans l'ordre des courses, si bien que la manche
	# qu'on venait de courir arrivait EN BAS. Sur une soiree de trente manches,
	# il fallait derouler pour retrouver celle dont on veut relire le
	# classement — c'est-a-dire, neuf fois sur dix, la derniere.
	#
	# Le journal des alertes pose deja la convention : « les cinq derniers
	# messages, le plus recent en tete ». Deux listes cote a cote qui se lisent
	# dans des sens opposes, c'est une hesitation a chaque fois.
	_history.clear()
	var results := _controller.history()
	for index: int in range(results.size() - 1, -1, -1):
		_add_history_item(results[index])


func _add_history_item(result: RaceResult) -> void:
	# Heure LOCALE : l'ISO UTC des fichiers se lisait avec deux heures d'ecart.
	var outcome := (
		"vainqueur %s (piste %d)" % [result.rider_name(result.winner()), result.winner() + 1]
	)
	# Une course ARRETEE n'a pas de vainqueur — la nommer ainsi serait un
	# resultat invente. Un plafond de securite, lui, en a un : « celui qui
	# mene gagne » (docs/02 §3), et il reste annonce comme tel.
	if result.was_stopped():
		outcome = "INTERROMPUE"
	_history.add_item("%s  %s  %s" % [result.finished_at_local(), result.mode, outcome])


func _on_race_finished(result: RaceResult) -> void:
	show_result(result)
	_rebuild_history()


## A L'ARRET DE LA VITRINE, LE TABLEAU REVIENT A LA DERNIERE VRAIE COURSE. Les
## manches de demonstration passent par `race_finished` comme les autres et
## laissaient leur podium « Démo 2 » a la place de celui d'Alice — pour des
## courses qui, dit le manuel, n'ont pas eu lieu.
func _on_demo_mode_changed(active: bool) -> void:
	if active:
		return
	var results := _controller.history()
	if results.is_empty():
		_table.text = ""
		_csv_label.text = "CSV : %s" % _controller.recorder.csv_path()
		return
	show_result(results.back())


func _on_history_selected(index: int) -> void:
	var result := _result_at(index)
	if result != null:
		show_result(result)


## La course derriere la ligne `index` de la liste. La liste est a l'ENVERS de
## l'historique — le plus recent en tete — et cette inversion vit ici seule :
## la poser a chaque appelant, c'est la garantie qu'un jour l'un d'eux lira la
## mauvaise course.
func _result_at(index: int) -> RaceResult:
	var results := _controller.history()
	var position := results.size() - 1 - index
	return null if position < 0 or position >= results.size() else results[position]


func _on_export() -> void:
	# Le dossier PARENT : journaux et courses y sont cote a cote, et c'est dans
	# les courses que se trouve le fichier a envoyer au developpeur.
	var races := _controller.recorder.races_dir()
	if races.is_empty():
		_csv_label.text = "Aucun résultat écrit pour l'instant."
		return
	OS.shell_open(races.get_base_dir())
