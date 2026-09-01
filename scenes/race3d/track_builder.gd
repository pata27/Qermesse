## Géométrie procédurale du vélodrome — docs/04 §4.
##
## Générée en code plutôt que modélisée : la piste dépend du nombre de couloirs
## actifs et de la distance de course, elle ne peut donc pas être un asset figé.
## Et un dépôt sans asset binaire est un dépôt sans asset orphelin — la faute
## que la v2 a payée.
class_name TrackBuilder
extends RefCounted

## Longueur du morceau de piste réellement affiché, CENTRÉ sur l'ancre. Le monde
## est recyclé autour d'elle : inutile de modéliser cinq kilomètres.
##
## Huit cents mètres, soit ±400 autour du centre du peloton : de quoi absorber
## un écart de huit cents mètres, très au-delà de tout ce qu'une course de
## rouleaux peut produire. Le coût est nul — la piste fait six triangles.
const SEGMENT_LENGTH_M := 800.0
const LANE_WIDTH_M := 1.6
## Relevé des bords. Un vélodrome est RAIDE — jusqu'à 45° dans les virages.
## Six mètres de large pour deux de haut donnait une rampe molle qui remplissait
## l'écran d'un plan gris sans rien raconter.
const BANK_WIDTH_M := 1.7
const BANK_HEIGHT_M := 1.55
## Pas de répétition du décor. Tout ce qui se répète le long de la piste —
## poteaux, charpente — utilise ce pas, ce qui permet de faire défiler le décor
## en le décalant modulo cette valeur : l'illusion est alors continue.
const SCROLL_PERIOD_M := 10.0


## Surface de roulement plus ses deux relevés, en un seul maillage.
static func build_mesh(lane_count: int) -> ArrayMesh:
	var lanes := clampi(lane_count, 1, 4)
	var half := float(lanes) * LANE_WIDTH_M * 0.5

	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	# Profil transversal : plat extérieur, relevé, piste, relevé, plat.
	# Les plats terminent la piste au lieu de la laisser flotter dans le noir,
	# et occupent la place que les relevés dévoraient auparavant.
	var apron := 9.0
	var profile := [
		Vector3(-half - BANK_WIDTH_M - apron, BANK_HEIGHT_M, 0.0),
		Vector3(-half - BANK_WIDTH_M, BANK_HEIGHT_M, 0.0),
		Vector3(-half, 0.0, 0.0),
		Vector3(half, 0.0, 0.0),
		Vector3(half + BANK_WIDTH_M, BANK_HEIGHT_M, 0.0),
		Vector3(half + BANK_WIDTH_M + apron, BANK_HEIGHT_M, 0.0),
	]

	# Normales calculées d'après le PROFIL, et non forcées vers le haut : les
	# relevés sont inclinés, et les éclairer comme un sol plat les faisait
	# ressortir en gris clair uniforme, à contre-emploi de la silhouette de
	# vélodrome qu'ils sont censés donner.
	var profile_normals: Array[Vector3] = []
	for index: int in range(profile.size()):
		var previous: Vector3 = profile[maxi(index - 1, 0)]
		var following: Vector3 = profile[mini(index + 1, profile.size() - 1)]
		var tangent := (following - previous).normalized()
		# Perpendiculaire au profil, dans le plan transversal, tournée vers le haut.
		profile_normals.append(Vector3(-tangent.y, tangent.x, 0.0).normalized())

	var z_start := -SEGMENT_LENGTH_M * 0.5
	var z_end := SEGMENT_LENGTH_M * 0.5
	var rows := 2
	for row: int in range(rows):
		var z: float = lerpf(z_start, z_end, float(row) / float(rows - 1))
		for index: int in range(profile.size()):
			var point: Vector3 = profile[index]
			vertices.append(Vector3(point.x, point.y, z))
			uvs.append(Vector2(point.x, z))
			normals.append(profile_normals[index])

	var columns := profile.size()
	for row: int in range(rows - 1):
		for column: int in range(columns - 1):
			var a := row * columns + column
			var b := a + 1
			var c := a + columns
			var d := c + 1
			# ORDRE HORAIRE vu de dessus. L'ordre inverse produisait des faces
			# arrière : `cull_disabled` les laissait voir, mais Godot retournait
			# la normale, le produit N·L devenait négatif, et la piste restait
			# NOIRE malgré des normales déclarées vers le haut. Symptôme
			# trompeur — l'émission des lignes s'affichait, elle, parfaitement.
			indices.append_array([a, b, c, b, d, c])

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
## Abscisse du couloir `lane` (indice d'AFFICHAGE, pas numéro de piste).
##
## Le signe compte, et il était faux depuis le début. La caméra regarde vers les
## Z croissants ; en repère droitier, son axe « droite » est donc −X, et le
## monde apparaît en MIROIR à l'écran. La piste 1 se retrouvait à droite de
## l'image et la piste 4 à gauche. L'indice d'affichage croît maintenant vers
## les X décroissants, de sorte que le premier couloir soit à gauche.
static func lane_x(lane: int, lane_count: int) -> float:
	var lanes := clampi(lane_count, 1, 4)
	var half := float(lanes) * LANE_WIDTH_M * 0.5
	return half - (float(lane) + 0.5) * LANE_WIDTH_M


## Main courante au sommet de chaque relevé. Sans elle, la piste se dissout
## dans le noir et l'œil ne sait plus où elle s'arrête.
static func build_rails(lane_count: int) -> Node3D:
	var lanes := clampi(lane_count, 1, 4)
	var half := float(lanes) * LANE_WIDTH_M * 0.5 + BANK_WIDTH_M
	var rails := Node3D.new()
	rails.name = "Rails"

	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.16, 0.18, 0.22)
	material.roughness = 0.5
	material.metallic = 0.5
	material.emission_enabled = true
	material.emission = Color(0.35, 0.45, 0.62)
	material.emission_energy_multiplier = 0.5

	for side: int in [-1, 1]:
		var rail := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.09, 0.09, SEGMENT_LENGTH_M)
		rail.mesh = mesh
		rail.material_override = material
		rail.position = Vector3(float(side) * half, BANK_HEIGHT_M + 0.55, 0.0)
		rail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rails.add_child(rail)

		# Montants réguliers : ils donnent l'échelle et rythment le défilement.
		# En MultiMesh : couvrir huit cents mètres au pas de dix en demandait
		# quatre-vingts par côté, soit autant d'appels de rendu pour des boîtes
		# de six centimètres.
		var post_count := int(SEGMENT_LENGTH_M / SCROLL_PERIOD_M)
		var posts := MultiMeshInstance3D.new()
		var post_mesh := BoxMesh.new()
		post_mesh.size = Vector3(0.06, 0.60, 0.06)
		var multimesh := MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		multimesh.mesh = post_mesh
		multimesh.instance_count = post_count
		for index: int in range(post_count):
			multimesh.set_instance_transform(index, Transform3D(
				Basis.IDENTITY,
				Vector3(
					float(side) * half,
					BANK_HEIGHT_M + 0.25,
					-SEGMENT_LENGTH_M * 0.5 + float(index) * SCROLL_PERIOD_M
				)
			))
		posts.multimesh = multimesh
		posts.material_override = material
		posts.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rails.add_child(posts)

	return rails


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
