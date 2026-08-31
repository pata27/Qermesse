## Géométrie procédurale du vélodrome — docs/04 §4.
##
## Générée en code plutôt que modélisée : la piste dépend du nombre de couloirs
## actifs et de la distance de course, elle ne peut donc pas être un asset figé.
## Et un dépôt sans asset binaire est un dépôt sans asset orphelin — la faute
## que la v2 a payée.
class_name TrackBuilder
extends RefCounted

## Longueur du morceau de piste réellement affiché. Le monde est recyclé autour
## de l'ancre : inutile de modéliser cinq kilomètres.
const SEGMENT_LENGTH_M := 400.0
const LANE_WIDTH_M := 1.6
## Relevé des bords, qui donne la silhouette de vélodrome sans coûter un mesh.
const BANK_WIDTH_M := 6.0
const BANK_HEIGHT_M := 2.4


## Surface de roulement plus ses deux relevés, en un seul maillage.
static func build_mesh(lane_count: int) -> ArrayMesh:
	var lanes := clampi(lane_count, 1, 4)
	var half := float(lanes) * LANE_WIDTH_M * 0.5

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	# Profil transversal : relevé gauche, plat, relevé droit.
	var profile := [
		Vector3(-half - BANK_WIDTH_M, BANK_HEIGHT_M, 0.0),
		Vector3(-half, 0.0, 0.0),
		Vector3(half, 0.0, 0.0),
		Vector3(half + BANK_WIDTH_M, BANK_HEIGHT_M, 0.0),
	]

	var z_start := -SEGMENT_LENGTH_M * 0.25
	var z_end := SEGMENT_LENGTH_M * 0.75
	var rows := 2
	for row: int in range(rows):
		var z: float = lerpf(z_start, z_end, float(row) / float(rows - 1))
		for point: Vector3 in profile:
			vertices.append(Vector3(point.x, point.y, z))
			uvs.append(Vector2(point.x, z))
			normals.append(Vector3(0.0, 1.0, 0.0))

	var columns := profile.size()
	for row: int in range(rows - 1):
		for column: int in range(columns - 1):
			var a := row * columns + column
			var b := a + 1
			var c := a + columns
			var d := c + 1
			indices.append_array([a, c, b, b, c, d])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Abscisse du centre d'un couloir, dans le repère de la piste.
static func lane_x(lane: int, lane_count: int) -> float:
	var lanes := clampi(lane_count, 1, 4)
	var half := float(lanes) * LANE_WIDTH_M * 0.5
	return -half + (float(lane) + 0.5) * LANE_WIDTH_M


## Portique d'arrivée : deux montants et une poutre. Rendu visible de loin,
## comme l'exige docs/04 §4 pour le mode distance.
static func build_finish_gate(lane_count: int, color: Color) -> Node3D:
	var lanes := clampi(lane_count, 1, 4)
	var span := float(lanes) * LANE_WIDTH_M + 1.2
	var gate := Node3D.new()
	gate.name = "FinishGate"

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.02, 0.03, 0.05)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 3.0

	for side: int in [-1, 1]:
		var post := MeshInstance3D.new()
		var post_mesh := BoxMesh.new()
		post_mesh.size = Vector3(0.18, 3.4, 0.18)
		post.mesh = post_mesh
		post.material_override = material
		post.position = Vector3(float(side) * span * 0.5, 1.7, 0.0)
		gate.add_child(post)

	var beam := MeshInstance3D.new()
	var beam_mesh := BoxMesh.new()
	beam_mesh.size = Vector3(span, 0.22, 0.22)
	beam.mesh = beam_mesh
	beam.material_override = material
	beam.position = Vector3(0.0, 3.4, 0.0)
	gate.add_child(beam)

	return gate
