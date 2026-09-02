## Habillage de la fenêtre spectacle — docs/04 §5.
##
## Répond à la question que la scène seule laissait sans réponse : *quelle
## distance à faire, et où en est-on ?* Sans cet habillage, une course est
## jolie et illisible.
##
## **Lisibilité à trois mètres** (`docs/03` §6) : police d'au moins 32 px à
## 1080p, contraste élevé, et jamais d'information portée par la seule couleur —
## chaque rider porte son numéro de piste ET son nom à côté de sa teinte.
class_name RaceHud
extends CanvasLayer

## Écart minimal, en km/h, pour que le chiffre de vitesse soit RÉÉCRIT. Deux
## dixièmes : en dessous, on n'affiche plus une mesure mais son bruit.
const SPEED_STEP_KPH := 0.2
const BAND_HEIGHT := 132
const CARD_HEIGHT := 96
## Largeur des cartes. Élargies pour que la cadence tienne à droite sans
## chevaucher la distance, dont la longueur varie avec le mode.
const CARD_WIDTH := 700.0
const ALERT := Color("#FF3B30")
const INK := Color("#F2F5FA")
## Vert de départ, pour le « PARTEZ ! ». Le décompte doit changer de COULEUR au
## zéro : un chiffre qui devient un mot se lit trop tard quand on est penché sur
## son guidon.
const GO := Color("#2BE08A")
## Gris de second plan, pour les en-têtes et les mentions secondaires.
const MUTED := Color("#8A94A6")
## Colonnes du podium : place, coureur, temps, moyenne, pointe.
const PODIUM_COLUMNS := 5
## Délai avant l'apparition du podium, le temps que la célébration se joue.
const PODIUM_DELAY_S := 3.2
## Barre de tension : largeur totale, du −G au +G.
const TENSION_WIDTH := 760.0
const TENSION_HEIGHT := 26.0

var _controller: AppController
var _mode_label: Label
var _objective_label: Label
var _clock_label: Label
var _gap_label: Label
var _tension: Control
var _tension_bar: ColorRect
var _tension_left: Label
var _tension_right: Label
var _cards: Dictionary = {}  # lane -> Dictionary de contrôles
var _target_speed: Dictionary = {}  # lane -> km/h visés
var _shown_speed: Dictionary = {}  # lane -> km/h lissés
var _printed_speed: Dictionary = {}  # lane -> km/h effectivement écrits
var _overlay: CanvasLayer
var _countdown_veil: ColorRect
var _countdown_holder: Control
var _countdown_label: Label
var _countdown_pulse := 0.0
var _countdown_hold_s := 0.0
var _podium: ColorRect
var _podium_title: Label
var _podium_grid: GridContainer
var _podium_note: Label
var _podium_delay_s := 0.0
var _pending_result: RaceResult = null
var _notice: Label


func setup(controller: AppController) -> void:
	_controller = controller
	layer = 2
	_build()
	_controller.progress_updated.connect(_on_progress)
	_controller.countdown_tick.connect(_on_countdown)
	_controller.race_state_changed.connect(_on_state)
	_controller.race_finished.connect(_on_finished)
	_controller.rider_eliminated.connect(_on_eliminated)
	rebuild_cards()


func _build() -> void:
	var band := ColorRect.new()
	band.color = Color(0.043, 0.055, 0.078, 0.82)
	band.set_anchors_preset(Control.PRESET_TOP_WIDE)
	band.custom_minimum_size.y = BAND_HEIGHT
	band.size.y = BAND_HEIGHT
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(band)

	_mode_label = _make_label(28, INK)
	_mode_label.position = Vector2(36, 18)
	add_child(_mode_label)

	_objective_label = _make_label(40, INK)
	_objective_label.position = Vector2(36, 56)
	add_child(_objective_label)

	# Chrono en chiffres géants — docs/04 §5.
	_clock_label = _make_label(84, INK)
	_clock_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_clock_label.position.y = 14
	add_child(_clock_label)

	# Écart au centre de l'écran : c'est le sujet du mode poursuite (docs/04 §4).
	_gap_label = _make_label(120, INK)
	_gap_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_gap_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gap_label.position = Vector2(-320, 215)
	_gap_label.size.x = 640
	_gap_label.visible = false
	add_child(_gap_label)

	_build_tension()

	# LES PLEIN-ÉCRANS ONT LEUR PROPRE COUCHE.
	#
	# L'ordre de dessin d'un `CanvasLayer` suit l'ordre des enfants, et les
	# cartes des coureurs sont créées PLUS TARD, par `rebuild_cards`, à chaque
	# armement. Le décompte et le podium, construits ici, se retrouvaient donc
	# DESSOUS : le voile assombrissait la scène mais les barres de progression
	# et les cartes lui passaient par-dessus. Une couche supérieure règle la
	# question une fois pour toutes, quel que soit l'ordre de construction.
	_overlay = CanvasLayer.new()
	_overlay.name = "PleinEcran"
	_overlay.layer = layer + 1
	add_child(_overlay)

	_build_countdown()
	_build_podium()

	_notice = _make_label(44, ALERT)
	_notice.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_notice.position = Vector2(-420, BAND_HEIGHT + 16)
	_notice.size.x = 840
	add_child(_notice)


## Une carte par piste active. Reconstruites à chaque armement : le nombre de
## pistes peut changer d'une course à l'autre.
func rebuild_cards() -> void:
	for entry: Dictionary in _cards.values():
		(entry["root"] as Node).queue_free()
	_cards.clear()

	var lanes := _controller.roster.active_lanes()
	for index: int in range(lanes.size()):
		var lane: int = lanes[index]
		var rider := _controller.roster.rider(lane)
		var color := Color(rider.color)

		var root := Control.new()
		root.position = Vector2(36, BAND_HEIGHT + 28 + index * (CARD_HEIGHT + 12))
		root.size = Vector2(CARD_WIDTH, CARD_HEIGHT)
		root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(root)

		var backdrop := ColorRect.new()
		backdrop.color = Color(0.043, 0.055, 0.078, 0.66)
		backdrop.size = Vector2(CARD_WIDTH, CARD_HEIGHT)
		root.add_child(backdrop)

		# Pastille de couleur ET numéro de piste : jamais la couleur seule.
		var chip := ColorRect.new()
		chip.color = color
		chip.position = Vector2(0, 0)
		chip.size = Vector2(10, CARD_HEIGHT)
		root.add_child(chip)

		var name_label := _make_label(34, color)
		name_label.text = "P%d  %s" % [lane + 1, rider.display_name()]
		name_label.position = Vector2(26, 6)
		root.add_child(name_label)

		var speed_label := _make_label(40, INK)
		speed_label.position = Vector2(440, 2)
		root.add_child(speed_label)

		# Cadence — docs/04 §5. Déduite du développement déclaré par
		# l'opérateur, puisque le capteur ne mesure que le rouleau.
		var cadence_label := _make_label(28, MUTED)
		cadence_label.position = Vector2(CARD_WIDTH - 176.0, 52)
		cadence_label.size.x = 160
		cadence_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		root.add_child(cadence_label)

		var distance_label := _make_label(28, INK)
		distance_label.position = Vector2(26, 50)
		root.add_child(distance_label)

		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.position = Vector2(26, 84)
		bar.size = Vector2(510, 8)
		var style := StyleBoxFlat.new()
		style.bg_color = color
		bar.add_theme_stylebox_override("fill", style)
		root.add_child(bar)

		_cards[lane] = {
			"root": root,
			"speed": speed_label,
			"cadence": cadence_label,
			"distance": distance_label,
			"bar": bar,
			"name": name_label,
		}
	_refresh_objective()


## Anime le décompte : le chiffre entre agrandi puis se resserre, et l'annonce
## de départ s'efface d'elle-même.
## Fait apparaître le podium une fois la célébration jouée.
func _tick_podium(delta: float) -> void:
	if _pending_result == null:
		return
	_podium_delay_s -= delta
	if _podium_delay_s <= 0.0:
		_show_podium(_pending_result)
		_pending_result = null


func _animate_countdown(delta: float) -> void:
	if _countdown_veil == null or not _countdown_veil.visible:
		return
	_countdown_pulse = maxf(0.0, _countdown_pulse - delta * 3.2)
	var eased := _countdown_pulse * _countdown_pulse
	var scale := 1.0 + eased * 0.55
	_countdown_holder.pivot_offset = _countdown_holder.size * 0.5
	_countdown_holder.scale = Vector2(scale, scale)
	_countdown_veil.color.a = 0.72 - eased * 0.18

	if _countdown_hold_s > 0.0:
		_countdown_hold_s -= delta
		if _countdown_hold_s <= 0.0:
			_countdown_veil.visible = false


## Rapproche les chiffres affichés de leur cible. Séparé de `_on_progress` :
## celui-ci arrive au rythme du boîtier, pas à celui de l'écran, et un lissage
## piloté par un signal externe ne serait pas régulier.
func _process(delta: float) -> void:
	_animate_countdown(delta)
	_tick_podium(delta)
	if _target_speed.is_empty():
		return
	var alpha := 1.0 - exp(-delta * 4.0)
	for lane: int in _cards:
		if not _target_speed.has(lane):
			continue
		var shown: float = _shown_speed.get(lane, float(_target_speed[lane]))
		shown = lerpf(shown, float(_target_speed[lane]), alpha)
		_shown_speed[lane] = shown

		# HYSTÉRÉSIS SUR LE CHIFFRE, et pas seulement lissage de la valeur.
		#
		# Lisser ne suffit pas : la valeur lissée converge vers sa cible, et si
		# celle-ci oscille de un ou deux dixièmes, le dernier chiffre bascule à
		# chaque image. C'est ce battement qui se lit comme un scintillement,
		# quelle que soit la constante de temps.
		#
		# Le chiffre affiché ne bouge donc que si la valeur lissée s'en écarte
		# d'au moins `SPEED_STEP_KPH`. Il reste alors immobile à allure stable,
		# et suit franchement une accélération réelle.
		var printed: float = _printed_speed.get(lane, INF)
		if absf(shown - printed) < SPEED_STEP_KPH:
			continue
		_printed_speed[lane] = shown
		var card: Dictionary = _cards[lane]
		(card["speed"] as Label).text = "%5.1f km/h" % shown


## BARRE DE TENSION — docs/04 §5 : « entre −G et +G ».
##
## Elle est SIGNÉE, et c'est tout l'intérêt. Une barre de 0 à G ne dit que la
## taille de l'écart ; celle-ci dit aussi DE QUEL CÔTÉ il penche, en se
## remplissant depuis le centre vers le coureur qui mène et en prenant sa
## couleur. On lit d'un coup d'œil qui est en train de prendre le dessus, ce
## qui est exactement la question du mode poursuite.
##
## Le sens suit la position à l'écran : le meneur est-il dans un couloir plus à
## gauche que le poursuivi ? alors la barre penche à gauche. Sans cela le
## symbole contredirait ce que montre la scène.
func _build_tension() -> void:
	_tension = Control.new()
	_tension.name = "Tension"
	_tension.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_tension.position = Vector2(-TENSION_WIDTH * 0.5, 352)
	_tension.size = Vector2(TENSION_WIDTH, TENSION_HEIGHT)
	_tension.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tension.visible = false
	add_child(_tension)

	# Contour clair : sur un fond de piste sombre et animé, un rectangle
	# anthracite sans bord disparaît, et l'on ne voit plus par rapport à QUOI la
	# barre se remplit. Le contour est ce qui donne l'échelle du −G au +G.
	var border := ColorRect.new()
	border.color = Color(0.55, 0.62, 0.75, 0.95)
	border.set_anchors_preset(Control.PRESET_FULL_RECT)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tension.add_child(border)

	var track := ColorRect.new()
	track.color = Color(0.07, 0.09, 0.13, 0.95)
	track.set_anchors_preset(Control.PRESET_FULL_RECT)
	track.offset_left = 2.0
	track.offset_top = 2.0
	track.offset_right = -2.0
	track.offset_bottom = -2.0
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tension.add_child(track)

	_tension_bar = ColorRect.new()
	_tension_bar.color = INK
	_tension_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tension.add_child(_tension_bar)

	# Repère central : sans lui, une barre presque vide et une barre penchée à
	# gauche se ressemblent.
	var middle := ColorRect.new()
	middle.color = Color(0.75, 0.80, 0.88)
	middle.position = Vector2(TENSION_WIDTH * 0.5 - 1.0, -6.0)
	middle.size = Vector2(2.0, TENSION_HEIGHT + 12.0)
	middle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tension.add_child(middle)

	_tension_left = _make_label(26, MUTED)
	_tension_left.position = Vector2(0.0, TENSION_HEIGHT + 6.0)
	_tension.add_child(_tension_left)

	_tension_right = _make_label(26, MUTED)
	_tension_right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_tension_right.position = Vector2(TENSION_WIDTH - 200.0, TENSION_HEIGHT + 6.0)
	_tension_right.size.x = 200.0
	_tension.add_child(_tension_right)


## Place la barre pour un écart signé, exprimé en fraction de l'objectif.
func _set_tension(signed_ratio: float, tint: Color) -> void:
	var half := TENSION_WIDTH * 0.5
	var span := clampf(signed_ratio, -1.0, 1.0) * half
	_tension_bar.color = tint
	if span >= 0.0:
		_tension_bar.position = Vector2(half, 0.0)
	else:
		_tension_bar.position = Vector2(half + span, 0.0)
	_tension_bar.size = Vector2(absf(span), TENSION_HEIGHT)


## PODIUM ET ÉCRAN DE FIN — docs/04 §5 : « temps, vitesse moyenne et vitesse de
## pointe par rider ».
##
## Construit vide et masqué : il se remplit à l'arrivée. Le rendre à ce
## moment-là éviterait quelques nœuds, mais construire une interface pendant que
## la scène célèbre une arrivée est le meilleur moyen de faire hoqueter l'image
## au pire instant — c'est déjà la leçon des confettis et des volets.
func _build_podium() -> void:
	_podium = ColorRect.new()
	_podium.name = "Podium"
	_podium.color = Color(0.02, 0.03, 0.05, 0.88)
	_podium.set_anchors_preset(Control.PRESET_FULL_RECT)
	_podium.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_podium.visible = false
	_overlay.add_child(_podium)

	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 18)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_podium.add_child(column)

	_podium_title = _make_label(72, INK)
	_podium_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_podium_title)

	# Une grille plutôt que des libellés alignés à la main : les colonnes
	# doivent rester alignées quels que soient la longueur des noms et le
	# nombre de coureurs.
	_podium_grid = GridContainer.new()
	_podium_grid.columns = PODIUM_COLUMNS
	_podium_grid.add_theme_constant_override("h_separation", 44)
	_podium_grid.add_theme_constant_override("v_separation", 14)
	_podium_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	column.add_child(_podium_grid)

	_podium_note = _make_label(30, MUTED)
	_podium_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_podium_note)


## Remplit et montre le podium. Les temps, la moyenne et la pointe viennent du
## `RaceResult`, donc du moteur : rien n'est recalculé ici.
func _show_podium(result: RaceResult) -> void:
	for child: Node in _podium_grid.get_children():
		child.queue_free()

	# LA TROISIÈME COLONNE DÉPEND DU MODE. En mode temps, tout le monde
	# « arrive » à l'instant du gong (`rule_time.gd`) : un temps y serait le
	# même sur chaque ligne et ne dirait rien. C'est la DISTANCE qui classe, et
	# c'est elle qu'il faut montrer. En distance et en poursuite, c'est le temps.
	var timed := result.config == null or result.config.mode != RaceConfig.Mode.TIME
	var third := "Temps" if timed else "Distance"
	for header: String in ["", "Coureur", third, "Moyenne", "Pointe"]:
		var cell := _make_label(30, MUTED)
		cell.text = header
		_podium_grid.add_child(cell)

	for rank: int in range(result.ranking.size()):
		var rider: int = result.ranking[rank]
		var color := Color(_controller.roster.rider(rider).color)
		# La place et le nom prennent la couleur du coureur : c'est ainsi qu'on
		# le reconnaît depuis les gradins, pas par son nom.
		var place := _make_label(44, color)
		place.text = "%d%s" % [rank + 1, "er" if rank == 0 else "e"]
		_podium_grid.add_child(place)

		var who := _make_label(44, color)
		who.text = "P%d  %s" % [rider + 1, _controller.roster.rider(rider).display_name()]
		_podium_grid.add_child(who)

		var figure := _make_label(44, INK)
		if result.eliminated[rider]:
			figure.text = "éliminé"
		elif not timed:
			figure.text = "%.1f m" % result.distance_m[rider]
		elif result.finished_ms[rider] > 0:
			figure.text = "%.2f s" % (float(result.finished_ms[rider]) / 1000.0)
		else:
			# Un coureur peut ne pas avoir franchi la ligne : course
			# interrompue, lien perdu. On l'écrit plutôt que d'inventer un temps.
			figure.text = "—"
		_podium_grid.add_child(figure)

		var avg := _make_label(44, INK)
		avg.text = "%.1f km/h" % result.avg_kph[rider]
		_podium_grid.add_child(avg)

		var peak := _make_label(44, INK)
		peak.text = "%.1f km/h" % result.max_kph[rider]
		_podium_grid.add_child(peak)

	_podium_title.text = "INTERROMPUE" if result.interrupted else "ARRIVÉE"
	_podium_note.text = (
		result.interruption_note if result.interrupted
		else "%s — %s" % [_objective_label.text, result.end_reason_name()]
	)
	_podium.visible = true


## DÉCOMPTE PLEIN ÉCRAN — docs/04 §5.
##
## Synchronisé sur les trames `CD:` du firmware, JAMAIS sur une horloge PC : les
## LED physiques du boîtier et l'écran doivent annoncer la même chose. Un
## décompte qui avance d'une demi-seconde sur les LED est pire que pas de
## décompte du tout, parce qu'il fait partir les coureurs au mauvais moment.
##
## Il occupe tout l'écran parce que c'est le seul moment où l'on ne regarde rien
## d'autre.
func _build_countdown() -> void:
	_countdown_veil = ColorRect.new()
	_countdown_veil.name = "CountdownVeil"
	_countdown_veil.color = Color(0.02, 0.03, 0.05, 0.72)
	_countdown_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	_countdown_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_countdown_veil.visible = false
	_overlay.add_child(_countdown_veil)

	# Le chiffre vit dans un conteneur centré : c'est lui qu'on met à l'échelle,
	# sinon l'agrandissement se ferait depuis le coin haut-gauche du libellé.
	_countdown_holder = Control.new()
	_countdown_holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	_countdown_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_countdown_veil.add_child(_countdown_holder)

	_countdown_label = _make_label(300, INK)
	_countdown_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_countdown_holder.add_child(_countdown_label)


func _make_label(size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	# Contour sombre : indispensable sur un vidéoprojecteur pâle, où un texte
	# clair sur fond clair de piste devient illisible.
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.05))
	label.add_theme_constant_override("outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _refresh_objective() -> void:
	var config := _controller.current_config()
	_mode_label.text = "MODE %s" % config.mode_name().to_upper()
	match config.mode:
		RaceConfig.Mode.DISTANCE:
			_objective_label.text = "%.0f m" % config.distance_m
		RaceConfig.Mode.TIME:
			_objective_label.text = "%.0f s" % config.duration_s
		RaceConfig.Mode.PURSUIT:
			_objective_label.text = "ecart %.0f m" % config.gap_m
	var pursuit := config.mode == RaceConfig.Mode.PURSUIT
	_gap_label.visible = pursuit
	_tension.visible = pursuit


func _on_state(_previous: int, current: int) -> void:
	if current == RaceEngine.State.ARMING:
		rebuild_cards()
		_notice.text = ""
		# Une nouvelle course efface la précédente : le podium ne doit pas
		# rester par-dessus le décompte suivant.
		_podium.visible = false
		_pending_result = null
	elif current == RaceEngine.State.IDLE:
		_clock_label.text = ""


func _on_countdown(value: int) -> void:
	# Décompte synchronisé sur les trames CD:, jamais sur une horloge PC :
	# les LED physiques et l'écran doivent être d'accord (docs/04 §5).
	_clock_label.text = str(value) if value > 0 else "PARTEZ"
	_countdown_label.text = str(value) if value > 0 else "PARTEZ !"
	_countdown_label.add_theme_color_override(
		"font_color", GO if value <= 0 else INK
	)
	_countdown_veil.visible = true
	# Chaque annonce repart d'un pic : le chiffre entre gros et se resserre,
	# ce qui donne le battement du décompte.
	_countdown_pulse = 1.0
	# « PARTEZ ! » s'efface tout seul ; les chiffres restent jusqu'au suivant.
	_countdown_hold_s = 0.9 if value <= 0 else 0.0


func _on_progress(state: RaceState) -> void:
	var config := state.config
	_clock_label.text = "%.2f s" % (state.elapsed_ms / 1000.0)

	var leader := -1
	var trailer := -1
	for lane: int in _cards:
		if leader < 0 or state.distance_m[lane] > state.distance_m[leader]:
			leader = lane
		if trailer < 0 or state.distance_m[lane] < state.distance_m[trailer]:
			trailer = lane

	for lane: int in _cards:
		var card: Dictionary = _cards[lane]
		# Vitesse d'AFFICHAGE, lissée sur une seconde côté moteur, puis LISSÉE
		# ENCORE à l'écran par `_process`. La fenêtre d'une seconde supprime les
		# paliers de tick mais laisse le dixième battre entre deux valeurs
		# voisines à chaque rafraîchissement ; c'est ce battement qui se voyait.
		# Le chiffre affiché rejoint sa cible en continu, il ne s'y pose plus.
		_target_speed[lane] = state.display_speed_kph[lane]

		# La cadence suit la vitesse d'affichage, donc elle est déjà lissée.
		var development: float = maxf(_controller.settings.development_m, 0.5)
		var rpm := state.display_speed_kph[lane] / 3.6 / development * 60.0
		(card["cadence"] as Label).text = "%.0f tr/min" % rpm

		var done := state.distance_m[lane]
		match config.mode:
			RaceConfig.Mode.DISTANCE:
				# LA question de l'utilisateur : combien reste-t-il ?
				var left := maxf(0.0, config.distance_m - done)
				(card["distance"] as Label).text = (
					"%.0f m parcourus   —   reste %.0f m" % [done, left]
				)
				(card["bar"] as ProgressBar).value = (
					clampf(done / maxf(1.0, config.distance_m), 0.0, 1.0) * 100.0
				)
			RaceConfig.Mode.TIME:
				var remaining := maxf(0.0, config.duration_s - state.elapsed_ms / 1000.0)
				(card["distance"] as Label).text = (
					"%.0f m parcourus   —   reste %.1f s" % [done, remaining]
				)
				(card["bar"] as ProgressBar).value = (
					clampf(state.elapsed_ms / 1000.0 / maxf(1.0, config.duration_s), 0.0, 1.0)
					* 100.0
				)
			RaceConfig.Mode.PURSUIT:
				var behind := state.distance_m[leader] - done
				(card["distance"] as Label).text = (
					"%.0f m parcourus   —   %s"
					% [done, "en tete" if lane == leader else "a %.1f m" % behind]
				)
				(card["bar"] as ProgressBar).value = (
					clampf(1.0 - behind / maxf(1.0, config.gap_m), 0.0, 1.0) * 100.0
				)

		if state.eliminated[lane]:
			(card["name"] as Label).modulate = Color(0.55, 0.55, 0.55)

	if config.mode == RaceConfig.Mode.PURSUIT and leader >= 0 and trailer >= 0:
		var gap := state.distance_m[leader] - state.distance_m[trailer]
		_gap_label.text = "%.1f m" % gap
		var ratio := clampf(gap / maxf(1.0, config.gap_m), 0.0, 1.0)
		# Vire au rouge à l'approche du seuil — docs/04 §4. La barre, elle,
		# prend la couleur du MENEUR : c'est ce qui dit qui prend le dessus.
		_gap_label.add_theme_color_override("font_color", INK.lerp(ALERT, ratio))
		var lanes := _controller.roster.active_lanes()
		var sign := -1.0 if lanes.find(leader) < lanes.find(trailer) else 1.0
		_set_tension(ratio * sign, Color(_controller.roster.rider(leader).color))
		_tension_left.text = "−%.0f m" % config.gap_m
		_tension_right.text = "+%.0f m" % config.gap_m


func _on_eliminated(rider: int, rank: int, _gap_m: float) -> void:
	_notice.text = "PISTE %d ELIMINEE — rang %d" % [rider + 1, rank]


func _on_finished(result: RaceResult) -> void:
	var winner := result.winner()
	_notice.add_theme_color_override("font_color", INK)
	_notice.text = (
		"VAINQUEUR — P%d %s%s"
		% [
			winner + 1,
			_controller.roster.rider(winner).display_name(),
			"   [INTERROMPUE]" if result.interrupted else "",
		]
	)
	# Le podium laisse d'abord la célébration se jouer : arriver par-dessus les
	# bras levés et les confettis volerait le moment aux coureurs.
	_podium_delay_s = PODIUM_DELAY_S
	_pending_result = result
