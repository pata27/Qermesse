## Scène 3D du spectacle — docs/04 §4.
##
## Elle **lit** l'état de course, elle ne l'écrit jamais, et elle ne touche
## jamais au port série. C'est la contrainte que `docs/05` pose explicitement en
## levant le verrou « la donnée avant le pixel » : la scène doit rester correcte
## quel que soit le nombre de pistes réellement câblées.
##
## Toute la géométrie est procédurale. Aucun asset binaire dans le dépôt, donc
## aucun asset orphelin — la faute que la v2 a payée.
class_name RaceScene
extends Node3D

signal quality_changed(level_name: String)

const TRACK_SEGMENT_M := TrackBuilder.SEGMENT_LENGTH_M

var quality := RenderQuality.new()
var perf := PerfMonitor.new()

var _controller: AppController
var _camera_rig: CameraRig
var _track: MeshInstance3D
var _track_material: ShaderMaterial
var _crowd: Crowd
var _finish_gate: Node3D
var _environment: WorldEnvironment
var _hud: RaceHud
var _overlay: ColorRect
var _overlay_material: ShaderMaterial
var _blur: ColorRect
var _blur_material: ShaderMaterial

var _rigs: Dictionary = {}          # lane -> RiderRig
var _interpolators: Dictionary = {}  # lane -> RiderInterpolator
var _lane_count := 2
var _anchor_m := 0.0
var _finish_m := -1.0
var _leader_speed_kph := 0.0
var _auto_degrade := true


## `level` negatif : detection automatique (docs/04 §4).
func setup(controller: AppController, level: int = -1) -> void:
	_controller = controller
	quality.level = RenderQuality.detect() if level < 0 else (level as RenderQuality.Level)

	_build_environment()
	_build_track()
	_build_camera()
	_build_post_process()
	_build_hud()

	_controller.race_state_changed.connect(_on_race_state_changed)
	_controller.progress_updated.connect(_on_progress)
	_controller.rider_finished.connect(_on_rider_finished)
	_controller.rider_eliminated.connect(_on_rider_eliminated)
	_controller.countdown_tick.connect(_on_countdown)

	rebuild_riders()


## Reconstruit les riders d'après le roster. Appelée à chaque armement : le
## nombre de pistes actives peut changer entre deux courses.
func rebuild_riders() -> void:
	for rig: RiderRig in _rigs.values():
		rig.queue_free()
	_rigs.clear()
	_interpolators.clear()

	var lanes := _controller.roster.active_lanes()
	_lane_count = maxi(1, lanes.size())
	var segments := int(quality.option("trail_segments"))

	for lane: int in lanes:
		var rig := RiderRig.new()
		add_child(rig)
		rig.setup(lane, Color(_controller.roster.rider(lane).color), segments)
		_rigs[lane] = rig
		_interpolators[lane] = RiderInterpolator.new()

	if _hud != null:
		_hud.rebuild_cards()

	_rebuild_track_material()
	_crowd.build(int(quality.option("crowd_count")), float(_lane_count) * TrackBuilder.LANE_WIDTH_M)
	_reposition_riders(0.0)


func _build_environment() -> void:
	_environment = WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	# Anthracite de docs/04 §2 : le fond ne doit jamais concurrencer les néons.
	env.background_color = Color("#0B0E14")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#1A2030")
	# Ambiante réduite : trop d'ambiante écrase les ombres et rend tout plat.
	env.ambient_light_energy = 0.35

	env.glow_enabled = bool(quality.option("glow"))
	env.glow_intensity = 0.9
	env.glow_bloom = 0.25
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.glow_hdr_threshold = 0.85

	if bool(quality.option("volumetric_fog")):
		env.volumetric_fog_enabled = true
		env.volumetric_fog_density = 0.012
		env.volumetric_fog_emission = Color("#101828")
	env.fog_enabled = true
	env.fog_light_color = Color("#0B0E14")
	env.fog_density = 0.006

	if bool(quality.option("ssao")):
		env.ssao_enabled = true

	_environment = WorldEnvironment.new()
	_environment.environment = env
	add_child(_environment)

	# Deux lumières, et c'est le minimum : un corps ne prend du volume que s'il
	# est ÉCLAIRÉ. Avec une seule source rasante et beaucoup d'ambiante, les
	# cyclistes ressortaient plats.
	var key := DirectionalLight3D.new()
	key.name = "KeyLight"
	key.light_energy = 1.9
	key.light_color = Color("#CFE0FF")
	key.rotation_degrees = Vector3(-38.0, 42.0, 0.0)
	key.shadow_enabled = bool(quality.option("shadows"))
	add_child(key)

	# Contre-jour froid depuis l'arrière-gauche : il détache les silhouettes du
	# fond anthracite sans éclaircir la piste.
	var fill := DirectionalLight3D.new()
	fill.name = "FillLight"
	fill.light_energy = 0.7
	fill.light_color = Color("#4A6EA8")
	fill.rotation_degrees = Vector3(-16.0, -140.0, 0.0)
	fill.shadow_enabled = false
	add_child(fill)


func _build_track() -> void:
	_track = MeshInstance3D.new()
	_track.name = "Track"
	add_child(_track)

	_track_material = ShaderMaterial.new()
	_track_material.shader = load("res://art/shaders/track.gdshader")
	_track.material_override = _track_material

	_crowd = Crowd.new()
	_crowd.name = "Crowd"
	add_child(_crowd)


func _rebuild_track_material() -> void:
	_track.mesh = TrackBuilder.build_mesh(_lane_count)

	var colors := PackedColorArray()
	for lane: int in range(Protocol.MAX_RIDERS):
		colors.append(Color(_controller.roster.rider(lane).color))
	_track_material.set_shader_parameter("lane_colors", colors)
	_track_material.set_shader_parameter("lane_count", _lane_count)
	_track_material.set_shader_parameter("lane_width", TrackBuilder.LANE_WIDTH_M)
	_track_material.set_shader_parameter("track_color", Color("#161B26"))
	_track_material.set_shader_parameter("glow_boost", 1.0 if quality.option("glow") else 0.6)


func _build_camera() -> void:
	_camera_rig = CameraRig.new()
	_camera_rig.name = "CameraRig"
	add_child(_camera_rig)


## Deux couches, et la séparation n'est pas cosmétique.
##
## `overlay` ne lit pas l'image : vignettage et lignes de vitesse coûtent un
## quad. `blur` lit l'image, ce qui force Godot à en recopier les huit
## mégaoctets avant chaque dessin en 1080p — il reste donc MASQUÉ tant que
## l'effet n'est pas réellement demandé. Les fondre en un seul shader revenait
## à payer la copie en permanence, y compris au niveau de qualité le plus bas.
func _build_post_process() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)

	_blur_material = ShaderMaterial.new()
	_blur_material.shader = load("res://art/shaders/radial_blur.gdshader")
	_blur = ColorRect.new()
	_blur.name = "RadialBlur"
	_blur.material = _blur_material
	_blur.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blur.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_blur.visible = false
	layer.add_child(_blur)

	_overlay_material = ShaderMaterial.new()
	_overlay_material.shader = load("res://art/shaders/overlay.gdshader")
	_overlay = ColorRect.new()
	_overlay.name = "Overlay"
	_overlay.material = _overlay_material
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_overlay)


## L'habillage est INDISSOCIABLE de la scène : sans lui, on ne sait ni quelle
## distance il reste, ni où en est chaque rider. Une belle piste sans ces
## chiffres n'est pas un affichage de course.
func _build_hud() -> void:
	_hud = RaceHud.new()
	_hud.name = "Hud"
	add_child(_hud)
	_hud.setup(_controller)


func hud() -> RaceHud:
	return _hud


func camera() -> Camera3D:
	return _camera_rig.camera


func _on_race_state_changed(_previous: int, current: int) -> void:
	if current == RaceEngine.State.ARMING:
		rebuild_riders()
		_anchor_m = 0.0
		var config := _controller.current_config()
		_camera_rig.set_behaviour_for_mode(config.mode)
		_finish_m = config.distance_m if config.mode == RaceConfig.Mode.DISTANCE else -1.0
		_place_finish_gate()
	elif current == RaceEngine.State.FINISHED:
		_crowd.cheer()
		_camera_rig.punch(1.0)


func _place_finish_gate() -> void:
	if _finish_gate != null:
		_finish_gate.queue_free()
		_finish_gate = null
	if _finish_m <= 0.0:
		return
	_finish_gate = TrackBuilder.build_finish_gate(_lane_count, Color("#F2F5FA"))
	add_child(_finish_gate)


func _on_progress(state: RaceState) -> void:
	for lane: int in _interpolators:
		var interp: RiderInterpolator = _interpolators[lane]
		interp.push_sample(state.distance_m[lane], state.speed_kph[lane])
	_leader_speed_kph = 0.0
	for lane: int in _interpolators:
		_leader_speed_kph = maxf(_leader_speed_kph, state.speed_kph[lane])


func _on_rider_finished(rider: int, _elapsed_ms: int, _rank: int) -> void:
	if _rigs.has(rider):
		(_rigs[rider] as RiderRig).flash()
	if _interpolators.has(rider):
		(_interpolators[rider] as RiderInterpolator).freeze()
	_crowd.cheer()
	_camera_rig.punch(0.6)


func _on_rider_eliminated(rider: int, _rank: int, _gap_m: float) -> void:
	if _interpolators.has(rider):
		(_interpolators[rider] as RiderInterpolator).freeze()


func _on_countdown(_value: int) -> void:
	_camera_rig.punch(0.25)


func _process(delta: float) -> void:
	if _controller == null:
		return

	_reposition_riders(delta)
	_update_effects(delta)

	# docs/04 §4 : toute fonctionnalité qui fait passer sous 60 fps est dégradée.
	# Même remarque que dans l'outil de mesure : on déduit le fps du delta de
	# l'image, pas du compteur lissé du moteur.
	if _auto_degrade and perf.sample(delta, 1.0 / maxf(delta, 0.000001)):
		if quality.degrade():
			apply_quality()
			quality_changed.emit(quality.level_name())


func _reposition_riders(delta: float) -> void:
	var state := _controller.engine.race_state()
	var leader_m := 0.0
	var trailer_m := INF
	var positions: Dictionary = {}

	for lane: int in _interpolators:
		var interp: RiderInterpolator = _interpolators[lane]
		var shown := interp.update(delta)
		positions[lane] = shown
		leader_m = maxf(leader_m, shown)
		trailer_m = minf(trailer_m, shown)
	if trailer_m == INF:
		trailer_m = 0.0

	# L'ancre suit le leader : le monde est recyclé autour de lui, ce qui évite
	# de modéliser cinq kilomètres de piste et garde la précision flottante.
	_anchor_m = leader_m
	_track.position.z = 0.0
	_track_material.set_shader_parameter("anchor_m", _anchor_m)
	_track_material.set_shader_parameter(
		"band_intensity", clampf(_leader_speed_kph / 45.0, 0.25, 1.5)
	)

	for lane: int in _rigs:
		var rig: RiderRig = _rigs[lane]
		var z: float = float(positions[lane]) - _anchor_m
		rig.position = Vector3(TrackBuilder.lane_x(_lane_index(lane), _lane_count), 0.0, z)
		var eliminated := state != null and state.eliminated[lane]
		var finished := state != null and state.finished_ms[lane] > 0
		var speed := state.speed_kph[lane] if state != null else 0.0
		rig.advance(delta, speed, eliminated, finished)

	if _finish_gate != null:
		_finish_gate.position.z = _finish_m - _anchor_m
		_track_material.set_shader_parameter("finish_z", _finish_m - _anchor_m)
	else:
		_track_material.set_shader_parameter("finish_z", -1000.0)

	var spread := leader_m - trailer_m
	var lateral := float(_lane_count) * TrackBuilder.LANE_WIDTH_M
	if _finish_m > 0.0:
		_camera_rig.consider_photo_finish(spread, _finish_m - leader_m)
	_camera_rig.note_speed(delta, _leader_speed_kph)
	_camera_rig.aim(0.0, spread, lateral, _leader_speed_kph)
	_camera_rig.advance(delta)


## Position du couloir à l'écran : les pistes actives sont resserrées au centre,
## sinon une course à deux riders sur les pistes 0 et 3 laisserait un trou.
func _lane_index(lane: int) -> int:
	var lanes := _controller.roster.active_lanes()
	var index := lanes.find(lane)
	return index if index >= 0 else lane


func _update_effects(delta: float) -> void:
	_crowd.react(delta, _leader_speed_kph)

	# Les lignes de vitesse n'apparaissent qu'au-delà d'un seuil : présentes en
	# permanence, elles cesseraient de signifier « vite ».
	var ratio := clampf((_leader_speed_kph - 28.0) / 32.0, 0.0, 1.0)
	_overlay_material.set_shader_parameter(
		"intensity", ratio if quality.option("speed_lines") else 0.0
	)

	# Le flou n'est présent à l'écran que lorsqu'il sert réellement : c'est le
	# masquage du noeud, et non un paramètre mis à zéro, qui évite la copie.
	var wants_blur: bool = bool(quality.option("radial_blur")) and ratio > 0.02
	_blur.visible = wants_blur
	if wants_blur:
		_blur_material.set_shader_parameter("strength", ratio * 0.8)


## Réapplique le profil courant — après une dégradation, ou un choix manuel.
func apply_quality() -> void:
	var env := _environment.environment
	env.glow_enabled = bool(quality.option("glow"))
	env.volumetric_fog_enabled = bool(quality.option("volumetric_fog"))
	env.ssao_enabled = bool(quality.option("ssao"))
	_crowd.build(int(quality.option("crowd_count")), float(_lane_count) * TrackBuilder.LANE_WIDTH_M)
	_track_material.set_shader_parameter("glow_boost", 1.0 if quality.option("glow") else 0.6)
	# Les traînées se reconstruisent d'elles-mêmes à la prochaine image, avec
	# le nombre de segments du nouveau profil.


func set_auto_degrade(enabled: bool) -> void:
	_auto_degrade = enabled
