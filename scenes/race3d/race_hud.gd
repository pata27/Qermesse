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

const BAND_HEIGHT := 132
const CARD_HEIGHT := 96
const ALERT := Color("#FF3B30")
const INK := Color("#F2F5FA")

var _controller: AppController
var _mode_label: Label
var _objective_label: Label
var _clock_label: Label
var _gap_label: Label
var _tension: ProgressBar
var _cards: Dictionary = {}  # lane -> Dictionary de contrôles
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
	_gap_label.position = Vector2(-320, 190)
	_gap_label.size.x = 640
	_gap_label.visible = false
	add_child(_gap_label)

	_tension = ProgressBar.new()
	_tension.show_percentage = false
	_tension.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_tension.position = Vector2(-300, 330)
	_tension.size = Vector2(600, 18)
	_tension.visible = false
	add_child(_tension)

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
		root.size = Vector2(560, CARD_HEIGHT)
		root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(root)

		var backdrop := ColorRect.new()
		backdrop.color = Color(0.043, 0.055, 0.078, 0.66)
		backdrop.size = Vector2(560, CARD_HEIGHT)
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
		speed_label.position = Vector2(330, 2)
		root.add_child(speed_label)

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
			"distance": distance_label,
			"bar": bar,
			"name": name_label,
		}
	_refresh_objective()


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
	elif current == RaceEngine.State.IDLE:
		_clock_label.text = ""


func _on_countdown(value: int) -> void:
	# Décompte synchronisé sur les trames CD:, jamais sur une horloge PC :
	# les LED physiques et l'écran doivent être d'accord (docs/04 §5).
	_clock_label.text = str(value) if value > 0 else "PARTEZ"


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
		(card["speed"] as Label).text = "%5.1f km/h" % state.speed_kph[lane]

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
		_tension.value = ratio * 100.0
		# Vire au rouge à l'approche du seuil — docs/04 §4.
		_gap_label.add_theme_color_override("font_color", INK.lerp(ALERT, ratio))


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
