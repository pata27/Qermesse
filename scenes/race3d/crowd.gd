## Tribunes et foule instanciée — docs/04 §4.
##
## Un `MultiMesh` d'un seul quad : deux mille spectateurs pour un appel de rendu.
## Sur un GPU intégré, c'est la seule façon de peupler des tribunes sans manger
## le budget des 60 fps. La foule est aussi le premier effet coupé au niveau bas.
class_name Crowd
extends Node3D

const ROW_COUNT := 8
const ROW_RISE_M := 0.85
const ROW_DEPTH_M := 1.0

var _material: ShaderMaterial
var _excitement := 0.0


func build(count: int, lane_span_m: float, seed_value: int = 4242) -> void:
	for child: Node in get_children():
		child.queue_free()
	if count <= 0:
		return

	_material = ShaderMaterial.new()
	_material.shader = load("res://art/shaders/crowd.gdshader")

	var quad := QuadMesh.new()
	quad.size = Vector2(0.55, 1.1)

	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value

	# Deux tribunes, de part et d'autre de la piste.
	for side: int in [-1, 1]:
		var instance := MultiMeshInstance3D.new()
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.use_colors = false
		multimesh.mesh = quad
		var half := count / 2
		multimesh.instance_count = half

		var base_x := float(side) * (lane_span_m * 0.5 + TrackBuilder.BANK_WIDTH_M + 1.5)
		for i: int in range(half):
			var row := i % ROW_COUNT
			var along := rng.randf_range(-90.0, 260.0)
			var x := base_x + float(side) * float(row) * ROW_DEPTH_M
			var y := TrackBuilder.BANK_HEIGHT_M + 0.8 + float(row) * ROW_RISE_M
			var jitter := rng.randf_range(-0.22, 0.22)
			var transform := Transform3D(Basis.IDENTITY, Vector3(x + jitter, y, along))
			multimesh.set_instance_transform(i, transform)

		instance.multimesh = multimesh
		instance.material_override = _material
		# Les spectateurs sont loin : inutile de les faire projeter des ombres.
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)


## La foule réagit à l'accélération et au franchissement — docs/04 §4.
func react(delta: float, speed_kph: float) -> void:
	if _material == null:
		return
	var target := clampf((speed_kph - 25.0) / 45.0, 0.0, 1.0)
	_excitement = lerpf(_excitement, target, clampf(delta * 1.5, 0.0, 1.0))
	_material.set_shader_parameter("excitement", _excitement)


func cheer() -> void:
	_excitement = 1.0
	if _material != null:
		_material.set_shader_parameter("excitement", _excitement)
