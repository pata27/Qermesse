## PODIUM ET ÉCRAN DE FIN — docs/04 §5 : « temps, vitesse moyenne et vitesse de
## pointe par rider ».
##
## Sorti de `race_hud.gd`, qui passait les mille lignes que le projet s'impose.
## La frontière est nette : ce fichier ne connaît que le résultat d'une course
## et sa mise en page. Ce qu'il faut effacer du reste de l'habillage pendant
## qu'il s'affiche relève du HUD, qui possède ces widgets, et y est resté.
##
## Construit vide et masqué : il se remplit à l'arrivée. Le rendre à ce
## moment-là éviterait quelques nœuds, mais construire une interface pendant que
## la scène célèbre une arrivée est le meilleur moyen de faire hoqueter l'image
## au pire instant — c'est déjà la leçon des confettis et des volets.
class_name RacePodium
extends ColorRect

## Cinq colonnes hors poursuite, six avec la distance parcourue.
const COLUMNS := 5

var _controller: AppController
var _title: Label
var _grid: GridContainer
var _note: Label


func setup(controller: AppController) -> void:
	_controller = controller
	name = "Podium"
	color = Color(0.02, 0.03, 0.05, 0.88)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 18)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)

	_title = RaceHud.make_label(72, RaceHud.INK)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_title)

	# Une grille plutôt que des libellés alignés à la main : les colonnes
	# doivent rester alignées quels que soient la longueur des noms et le
	# nombre de coureurs.
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", 44)
	_grid.add_theme_constant_override("v_separation", 14)
	_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(_grid)

	_note = RaceHud.make_label(30, RaceHud.MUTED)
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_note)


## Remplit et montre le podium. Les temps, la moyenne et la pointe viennent du
## `RaceResult`, donc du moteur : rien n'est recalculé ici. `objective` est le
## libellé de l'objectif, que seule la bannière connaît.
func show_result(result: RaceResult, objective: String) -> void:
	for child: Node in _grid.get_children():
		child.queue_free()

	# LA TROISIÈME COLONNE DÉPEND DU MODE. En mode temps, tout le monde
	# « arrive » à l'instant du gong (`rule_time.gd`) : un temps y serait le
	# même sur chaque ligne et ne dirait rien. C'est la DISTANCE qui classe, et
	# c'est elle qu'il faut montrer. En distance et en poursuite, c'est le temps.
	var mode: RaceConfig.Mode = (
		RaceConfig.Mode.DISTANCE if result.config == null else result.config.mode
	)
	var timed := mode != RaceConfig.Mode.TIME
	# En poursuite, DEUX chiffres par coureur : le temps couru avant l'élimination
	# — ou l'arrivée pour le survivant — et la distance parcourue. « Éliminé »
	# seul ne disait ni quand ni après combien, et c'est tout l'intérêt.
	var pursuit := mode == RaceConfig.Mode.PURSUIT
	var headers: Array[String] = ["", "Coureur", "Temps" if timed else "Distance"]
	if pursuit:
		headers.append("Distance")
	headers.append_array(["Moyenne", "Pointe"])
	_grid.columns = headers.size()
	for header: String in headers:
		var cell := RaceHud.make_label(30, RaceHud.MUTED)
		cell.text = header
		_grid.add_child(cell)

	for rank: int in range(result.ranking.size()):
		var rider: int = result.ranking[rank]
		var color_of := Color(_controller.roster.rider(rider).color)
		# La place et le nom prennent la couleur du coureur : c'est ainsi qu'on
		# le reconnaît depuis les gradins, pas par son nom.
		var place := RaceHud.make_label(44, color_of)
		place.text = "%d%s" % [rank + 1, "er" if rank == 0 else "e"]
		_grid.add_child(place)

		var who := RaceHud.make_label(44, color_of)
		# LES NOMS DU DEPART, portes par le resultat — pas le roster courant.
		# Renommer les pistes entre deux courses ne reecrit pas l'histoire, et
		# l'ecran public doit dire la meme chose que le tableau operateur.
		who.text = "P%d  %s" % [rider + 1, Roster.shorten(result.rider_name(rider))]
		_grid.add_child(who)

		var figure := RaceHud.make_label(44, RaceHud.INK)
		if not timed:
			figure.text = "%.1f m" % result.distance_m[rider]
		elif result.finished_ms[rider] > 0:
			figure.text = "%.2f s" % (float(result.finished_ms[rider]) / 1000.0)
			# docs/02 §1 : meme trame, ex aequo — l'ecran le dit.
			if result.is_dead_heat(rider):
				figure.text += "  photo-finish"
		elif result.eliminated[rider] and result.eliminated_ms[rider] > 0:
			figure.text = "%.2f s ✕" % (float(result.eliminated_ms[rider]) / 1000.0)
		elif result.eliminated[rider]:
			figure.text = "éliminé"
		else:
			# Survivant d'un plafond de poursuite, ou course interrompue : il a
			# couru jusqu'à la fin de la course — c'est ce temps-là. Le motif
			# de fin, affiché avec le podium, dit que ce n'est pas une arrivée.
			figure.text = "%.2f s" % (float(result.raced_ms(rider)) / 1000.0)
		_grid.add_child(figure)

		if pursuit:
			var covered := RaceHud.make_label(44, RaceHud.INK)
			covered.text = "%.1f m" % result.distance_m[rider]
			_grid.add_child(covered)

		var avg := RaceHud.make_label(44, RaceHud.INK)
		avg.text = "%.1f km/h" % result.avg_kph[rider]
		_grid.add_child(avg)

		var peak := RaceHud.make_label(44, RaceHud.INK)
		peak.text = "%.1f km/h" % result.max_kph[rider]
		_grid.add_child(peak)

	# UNE COURSE DECIDEE AU PLAFOND N'EST PAS UNE COURSE ARRETEE. docs/02 §3 :
	# au plafond de securite, « celui qui mene gagne » — c'est une fin
	# legitime, avec un vainqueur, et l'annoncer INTERROMPUE en gros devant le
	# public dit le contraire. Seul un abandon — arret operateur, lien perdu,
	# fermeture — n'a pas de vainqueur. C'est la regle deja appliquee a la
	# liste des courses du jour, et jamais reportee ici.
	_title.text = "INTERROMPUE" if result.was_stopped() else "ARRIVÉE"
	_note.text = (
		result.interruption_note if result.interrupted
		else "%s — %s" % [objective, result.end_reason_name()]
	)
	visible = true


## Tout le texte du podium, TITRE ET MOTIF COMPRIS : c'est le contenu qui est
## la promesse, pas la disposition. La version precedente ne rendait que la
## grille — un test sur le titre ne pouvait donc rien voir.
func text() -> String:
	var parts: PackedStringArray = [_title.text]
	for child: Node in _grid.get_children():
		if child is Label:
			parts.append((child as Label).text)
	parts.append(_note.text)
	return " ".join(parts)
