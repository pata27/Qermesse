## Tribunes et foule instanciée — docs/04 §4.
##
## Un `MultiMesh` d'un seul quad : deux mille spectateurs pour un appel de rendu.
## Sur un GPU intégré, c'est la seule façon de peupler des tribunes sans manger
## le budget des 60 fps. La foule est aussi le premier effet coupé au niveau bas.
class_name Crowd
extends Node3D

const ROW_COUNT := 14
const ROW_RISE_M := 0.62
const ROW_DEPTH_M := 0.90
## Recul des gradins par rapport au sommet du relevé. Cinq mètres mettaient les
## spectateurs quasiment sur la piste : les plus proches occupaient un dixième
## de l'écran et se lisaient comme des monolithes.
const STAND_SETBACK_M := 5.5

var _material: ShaderMaterial
var _excitement := 0.0
var _periodic: Node3D


func build(count: int, lane_span_m: float, seed_value: int = 4242) -> void:
	for child: Node in get_children():
		child.queue_free()
	# Les gradins sont construits MÊME sans spectateurs : sans eux, la foule
	# flottait dans le vide au-dessus de la piste, et l'horizon n'était qu'une
	# bande grise sans structure.
	_build_stands(lane_span_m)
	if count <= 0:
		return

	_material = ShaderMaterial.new()
	_material.shader = load("res://art/shaders/crowd.gdshader")
	_material.set_shader_parameter("span_m", TrackBuilder.SEGMENT_LENGTH_M * 0.7)

	# Un spectateur assis : plus large que haut au-dessus de la taille.
	var quad := QuadMesh.new()
	quad.size = Vector2(0.46, 0.78)

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

		var base_x := float(side) * (
			lane_span_m * 0.5 + TrackBuilder.BANK_WIDTH_M + STAND_SETBACK_M
		)
		for i: int in range(half):
			var row := i % ROW_COUNT
			# Répartis symétriquement autour de l'ancre : depuis que celle-ci est
			# au milieu du peloton, le dernier peut se trouver loin DERRIÈRE, et
			# une tribune vide de ce côté se voyait immédiatement dans la vue
			# scindée.
			var reach := TrackBuilder.SEGMENT_LENGTH_M * 0.35
			var along := rng.randf_range(-reach, reach)
			var x := base_x + float(side) * float(row) * ROW_DEPTH_M
			# Assis SUR la marche correspondante, plus flottant au-dessus.
			var y := TrackBuilder.BANK_HEIGHT_M + 0.95 + float(row) * ROW_RISE_M * 0.5
			var jitter := rng.randf_range(-0.22, 0.22)
			var transform := Transform3D(Basis.IDENTITY, Vector3(x + jitter, y, along))
			multimesh.set_instance_transform(i, transform)

		instance.multimesh = multimesh
		instance.material_override = _material
		# Les spectateurs sont loin : inutile de les faire projeter des ombres.
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(instance)


## Fait défiler la foule et la charpente avec la course.
##
## Les deux ne défilent pas de la même façon, et c'est le fond du problème : la
## charpente est régulièrement espacée, donc un simple modulo suffit ; les
## spectateurs sont répartis au hasard et doivent reboucler un par un, ce dont
## leur shader se charge. Les gradins eux-mêmes ne défilent pas du tout — ce
## sont des boîtes uniformes sur toute la longueur, rien n'y trahirait un
## mouvement.
func scroll(anchor_m: float) -> void:
	if _periodic != null:
		_periodic.position.z = -fposmod(anchor_m, TrackBuilder.SCROLL_PERIOD_M)
	if _material != null:
		_material.set_shader_parameter("scroll_m", anchor_m)


## Gradins : une marche par rangée, de part et d'autre. Quelques boîtes
## suffisent — c'est la STRUCTURE qui manquait, pas le détail.
func _build_stands(lane_span_m: float) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.055, 0.065, 0.09)
	material.roughness = 0.9
	material.metallic = 0.0

	# Nez de marche : un liseré FIN et discret. Des marches entières émissives
	# une sur trois dessinaient une silhouette dentelée qui se lisait comme une
	# ligne de gratte-ciels, pas comme une tribune.
	var nosing := StandardMaterial3D.new()
	nosing.albedo_color = Color(0.10, 0.12, 0.16)
	nosing.roughness = 0.7
	nosing.emission_enabled = true
	nosing.emission = Color(0.22, 0.32, 0.48)
	nosing.emission_energy_multiplier = 0.55

	var base_x := lane_span_m * 0.5 + TrackBuilder.BANK_WIDTH_M + STAND_SETBACK_M
	for side: int in [-1, 1]:
		for row: int in range(ROW_COUNT):
			var step := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			mesh.size = Vector3(ROW_DEPTH_M, ROW_RISE_M, TrackBuilder.SEGMENT_LENGTH_M)
			step.mesh = mesh
			# Chaque marche monte et recule : le profil en escalier se lit de
			# loin, ce qui donne le volume d'une tribune.
			step.position = Vector3(
				float(side) * (base_x + float(row) * ROW_DEPTH_M),
				TrackBuilder.BANK_HEIGHT_M + 0.4 + float(row) * ROW_RISE_M * 0.5,
				0.0
			)
			step.material_override = material
			step.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(step)

			# Liseré au bord de chaque marche : il donne le rythme des gradins
			# sans en faire une masse lumineuse.
			var lip := MeshInstance3D.new()
			var lip_mesh := BoxMesh.new()
			lip_mesh.size = Vector3(0.06, 0.05, TrackBuilder.SEGMENT_LENGTH_M)
			lip.mesh = lip_mesh
			lip.material_override = nosing
			lip.position = step.position + Vector3(
				float(-side) * ROW_DEPTH_M * 0.5, ROW_RISE_M * 0.25, 0.0
			)
			lip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(lip)

		# Paroi de fond : elle FERME la tribune. Sans elle, le sommet des
		# gradins se découpe sur du noir absolu et se lit comme une skyline.
		var wall := MeshInstance3D.new()
		var wall_mesh := BoxMesh.new()
		wall_mesh.size = Vector3(0.4, 9.0, TrackBuilder.SEGMENT_LENGTH_M)
		wall.mesh = wall_mesh
		wall.material_override = material
		wall.position = Vector3(
			float(side) * (base_x + float(ROW_COUNT) * ROW_DEPTH_M + 0.3),
			TrackBuilder.BANK_HEIGHT_M + 4.0,
			0.0
		)
		wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(wall)

	# Charpente : quelques poutres en travers, très haut. Elles ferment le
	# volume et donnent l'échelle du bâtiment — sans elles, au-dessus des
	# tribunes il n'y avait que du noir absolu, sans plafond ni hauteur.
	var truss_material := StandardMaterial3D.new()
	truss_material.albedo_color = Color(0.07, 0.08, 0.11)
	truss_material.roughness = 0.85
	truss_material.emission_enabled = true
	truss_material.emission = Color(0.16, 0.22, 0.34)
	truss_material.emission_energy_multiplier = 0.28

	# En MultiMesh, pour la même raison que les montants : quatre-vingts poutres
	# sur huit cents mètres feraient quatre-vingts appels de rendu.
	var span := (base_x + float(ROW_COUNT) * ROW_DEPTH_M) * 2.2
	var truss_count := int(TrackBuilder.SEGMENT_LENGTH_M / TrackBuilder.SCROLL_PERIOD_M)
	var trusses := MultiMeshInstance3D.new()
	var truss_mesh := BoxMesh.new()
	truss_mesh.size = Vector3(span, 0.35, 0.35)
	var truss_multi := MultiMesh.new()
	truss_multi.transform_format = MultiMesh.TRANSFORM_3D
	truss_multi.mesh = truss_mesh
	truss_multi.instance_count = truss_count
	for index: int in range(truss_count):
		truss_multi.set_instance_transform(index, Transform3D(
			Basis.IDENTITY,
			Vector3(
				0.0,
				9.5,
				-TrackBuilder.SEGMENT_LENGTH_M * 0.5 + float(index) * TrackBuilder.SCROLL_PERIOD_M
			)
		))
	trusses.multimesh = truss_multi
	trusses.material_override = truss_material
	trusses.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# La charpente est le seul élément de cette branche à devoir défiler : elle
	# est régulièrement espacée, donc un modulo suffit. Les gradins, eux, sont
	# des boîtes uniformes sur toute la longueur.
	_periodic = Node3D.new()
	_periodic.name = "DecorPeriodique"
	add_child(_periodic)
	_periodic.add_child(trusses)


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
