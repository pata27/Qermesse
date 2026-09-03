## Affichage du mode POURSUITE — docs/04 §5 : « l'écart occupe le centre de
## l'écran, avec la barre de tension entre −G et +G ».
##
## Sorti de `race_hud.gd`, qui avait repassé les mille lignes que le linter
## impose. La découpe suit un mode : tout ce qui ne s'affiche qu'en poursuite
## vit ici — le gros chiffre d'écart, la barre signée, la jauge « décision
## dans ». Le reste de l'habillage n'en sait rien.
##
## **À configurer AVANT d'entrer dans l'arbre**, comme `RacePodium` : `build()`
## pose les tailles et les positions, et un `Control` ajouté avant d'être
## dimensionné se retrouve de taille nulle.
class_name RaceTension
extends Control

## Largeur de la barre, et sa hauteur. Elle est lue de loin, sur un mur.
const WIDTH := 760.0
const HEIGHT := 26.0
## Raideur du lissage des barres, en 1/s.
const SMOOTHING := 10.0
## Le chiffre d'écart ne bouge que si l'écart lissé s'en éloigne d'autant.
const GAP_STEP_M := 0.15
const GAP_SMOOTHING := 5.0

var _gap_label: Label
var _bar: Control
var _bars: Array[ColorRect] = []
var _left: Label
var _right: Label
var _decision: Label

var _lead_target := 0.0
var _lead_shown := 0.0
var _lead_color := Color.WHITE
var _targets: Array = []
var _shown: Dictionary = {}

var _gap_target := 0.0
var _gap_shown := 0.0
var _gap_printed := INF
var _gap_scale := 1.0


## Construit le bloc. `centre_x` est l'abscisse autour de laquelle centrer :
## l'espace LIBRE à droite des cartes, pas le milieu de l'écran.
func build(centre_x: float) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_build_gap(centre_x)
	_build_bar(centre_x)


func _build_gap(centre_x: float) -> void:
	# Écart au centre de l'écran : c'est le sujet du mode poursuite (docs/04 §4).
	# Centré dans l'espace LIBRE à droite des cartes, pas au milieu de l'écran :
	# depuis que les cartes font 700 px, un bloc centré à 960 leur passait
	# dessus, et les compteurs de vitesse et de cadence marchaient sur la barre.
	_gap_label = RaceHud.make_label(120, RaceHud.INK)
	_gap_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gap_label.position = Vector2(centre_x - 320.0, 215)
	_gap_label.size.x = 640
	add_child(_gap_label)

## Le gros chiffre d'écart : lissé en continu, puis affiché avec hystérésis —
## la même recette que la vitesse, pour la même raison.
func _animate_gap(delta: float) -> void:
	var alpha := 1.0 - exp(-delta * GAP_SMOOTHING)
	_gap_shown = lerpf(_gap_shown, _gap_target, alpha)
	if absf(_gap_shown - _gap_printed) < GAP_STEP_M:
		return
	_gap_printed = _gap_shown
	_gap_label.text = "%.1f m" % _gap_shown
	# Vire au rouge à l'approche du seuil — docs/04 §4.
	_gap_label.add_theme_color_override(
		"font_color", RaceHud.INK.lerp(RaceHud.ALERT, clampf(_gap_shown / _gap_scale, 0.0, 1.0))
	)


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
func _build_bar(centre_x: float) -> void:
	_bar = Control.new()
	_bar.name = "Barre"
	_bar.position = Vector2(centre_x - WIDTH * 0.5, 352)
	_bar.size = Vector2(WIDTH, HEIGHT)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bar)

	# Contour clair : sur un fond de piste sombre et animé, un rectangle
	# anthracite sans bord disparaît, et l'on ne voit plus par rapport à QUOI la
	# barre se remplit. Le contour est ce qui donne l'échelle du −G au +G.
	var border := ColorRect.new()
	border.color = Color(0.55, 0.62, 0.75, 0.95)
	border.set_anchors_preset(Control.PRESET_FULL_RECT)
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.add_child(border)

	var track := ColorRect.new()
	track.color = Color(0.07, 0.09, 0.13, 0.95)
	track.set_anchors_preset(Control.PRESET_FULL_RECT)
	track.offset_left = 2.0
	track.offset_top = 2.0
	track.offset_right = -2.0
	track.offset_bottom = -2.0
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.add_child(track)

	# UN RECTANGLE PAR COUREUR. Le leader remplit la droite, chaque poursuivant
	# remplit la gauche de son retard, et les barres se superposent — la plus
	# longue dessinée en premier, donc derrière, pour que toutes restent visibles.
	for index: int in range(Protocol.MAX_RIDERS):
		var bar := ColorRect.new()
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar.visible = false
		_bar.add_child(bar)
		_bars.append(bar)

	# Repère central : sans lui, une barre presque vide et une barre penchée à
	# gauche se ressemblent.
	var middle := ColorRect.new()
	middle.color = Color(0.75, 0.80, 0.88)
	middle.position = Vector2(WIDTH * 0.5 - 1.0, -6.0)
	middle.size = Vector2(2.0, HEIGHT + 12.0)
	middle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar.add_child(middle)

	_left = RaceHud.make_label(26, RaceHud.MUTED)
	_left.position = Vector2(0.0, HEIGHT + 6.0)
	_bar.add_child(_left)

	_right = RaceHud.make_label(26, RaceHud.MUTED)
	_right.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_right.position = Vector2(WIDTH - 200.0, HEIGHT + 6.0)
	_right.size.x = 200.0
	_bar.add_child(_right)

	# La jauge « temps restant avant décision » — docs/02 §3 —, au centre sous
	# la barre, entre −G et +G : c'est l'autre façon dont la course peut tomber.
	_decision = RaceHud.make_label(26, RaceHud.MUTED)
	_decision.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_decision.position = Vector2(200.0, HEIGHT + 6.0)
	_decision.size.x = WIDTH - 400.0
	_bar.add_child(_decision)


## Place les barres. LE LEADER EST LA RÉFÉRENCE, pas la queue.
##
## Une seule barre « tête moins queue » avait un défaut visible à trois ou
## quatre coureurs : quand le dernier était éliminé, la queue changeait, l'écart
## se refermait et la barre du premier REDESCENDAIT alors qu'il n'avait pas
## ralenti — et les deuxième et troisième n'apparaissaient nulle part.
##
## Ici, à droite, l'avance du leader sur son dauphin, à sa couleur. À gauche,
## une barre par poursuivant, longueur = retard sur le leader en fraction de
## l'objectif : à −G, il est éliminé. Les barres se superposent, la plus longue
## derrière. Une élimination fait disparaître une barre sans déplacer les
## autres, puisque leur retard sur le leader n'a pas changé.
##
## `chasers` : tableau de `[retard_fraction, couleur]`, un par poursuivant.
## Ne fait que poser les CIBLES ; c'est `_layout_tension`, cadencé par l'écran,
## qui dessine. Alimentées brutes à chaque trame du boîtier, les barres
## tremblaient : la distance avance par ticks de 36 cm, soit près de trois
## pixels d'un coup sur une barre de cinquante mètres, cent fois par seconde.
func set_bars(lead_ratio: float, lead_color: Color, chasers: Array) -> void:
	_lead_target = clampf(lead_ratio, 0.0, 1.0)
	_lead_color = lead_color
	_targets = chasers


func _layout_bars(delta: float) -> void:
	var alpha := 1.0 - exp(-delta * SMOOTHING)
	var half := WIDTH * 0.5
	for bar: ColorRect in _bars:
		bar.visible = false

	_lead_shown = lerpf(_lead_shown, _lead_target, alpha)
	var lead_bar: ColorRect = _bars[0]
	lead_bar.color = _lead_color
	lead_bar.position = Vector2(half, 0.0)
	lead_bar.size = Vector2(_lead_shown * half, HEIGHT)
	lead_bar.visible = true

	# Lissage PAR COULEUR, la couleur identifiant le coureur : c'est ce qui
	# garde chaque barre continue quand l'ordre des retards change.
	var seen: Dictionary = {}
	var ordered: Array = []
	for entry: Array in _targets:
		var key := str(entry[1])
		var shown: float = lerpf(
			float(_shown.get(key, float(entry[0]))), float(entry[0]), alpha
		)
		_shown[key] = shown
		seen[key] = true
		ordered.append([shown, entry[1]])
	for key: String in _shown.keys():
		if not seen.has(key):
			_shown.erase(key)

	# Du plus en retard au moins en retard : le plus long est dessiné en
	# premier, donc derrière, et chaque couleur reste visible sur son bout.
	ordered.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) > float(b[0]))
	for index: int in range(mini(ordered.size(), _bars.size() - 1)):
		var entry: Array = ordered[index]
		var span := clampf(float(entry[0]), 0.0, 1.0) * half
		var bar: ColorRect = _bars[index + 1]
		bar.color = entry[1]
		bar.position = Vector2(half - span, 0.0)
		bar.size = Vector2(span, HEIGHT)
		bar.visible = true


## Cadencé par l'écran : le lissage et le dessin.
func advance(delta: float) -> void:
	if not visible:
		return
	_animate_gap(delta)
	_layout_bars(delta)


## Bornes affichées sous la barre, `−G` et `+G`.
func set_bounds(left_text: String, right_text: String) -> void:
	_left.text = left_text
	_right.text = right_text


## Cible du gros chiffre, et l'échelle sur laquelle il vire au rouge.
func set_gap(target: float, scale: float) -> void:
	_gap_target = target
	_gap_scale = maxf(scale, 0.001)


## Jauge « décision dans … » — docs/02 §3.
func set_decision(text: String, urgent: bool) -> void:
	_decision.text = text
	_decision.add_theme_color_override(
		"font_color", RaceHud.ALERT if urgent else RaceHud.MUTED
	)


## Remet le bloc à zéro entre deux courses : sans cela, la barre repartait de
## son dernier état et le chiffre décroissait depuis l'écart de la veille.
func reset() -> void:
	visible = false
	_gap_target = 0.0
	_gap_shown = 0.0
	_gap_printed = INF
	_lead_target = 0.0
	_lead_shown = 0.0
	_targets = []
	_shown.clear()
	_decision.text = ""


func gap_text() -> String:
	return _gap_label.text


func decision_text() -> String:
	return _decision.text
