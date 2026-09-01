## Le cycliste — modèle unique, quatre matériaux (docs/04 §4).
##
## **Ce qui doit se lire, à cinq mètres et sur un projecteur pâle : deux roues,
## un cadre, un corps penché.** Rien d'autre. La première version dessinait un
## amas de primitives dont la silhouette ne disait rien — corrigée après retour
## de l'utilisateur (`tasks/lessons.md`).
##
## Les jantes sont émissives à la couleur du couloir : ce sont elles qui portent
## l'identité du rider et qui rendent le vélo lisible sur une piste sombre. Le
## cadre reste sombre avec un liseré, pour que la silhouette se détache sans
## éblouir.
class_name RiderRig
extends Node3D

## Roue de 700c : 0,34 m de rayon. Toutes les proportions en découlent.
const WHEEL_RADIUS_M := 0.34
const WHEELBASE_M := 1.02
## Le pédalier tourne plus lentement que la roue — sinon les jambes s'affolent.
const CRANK_RATIO := 0.34
## Manivelle de 170 mm, comme sur un vrai vélo de piste.
const CRANK_LENGTH_M := 0.17
const MAX_LEAN_RAD := 0.20

var lane: int = 0
var color: Color = Color("#00E5FF")

var _jersey_material: ShaderMaterial
var _rim_material: StandardMaterial3D
var _frame_material: StandardMaterial3D
var _trail_material: ShaderMaterial
var _trail: MeshInstance3D
var _crank: Node3D
var _legs: Array[MeshInstance3D] = []
var _wheels: Array[Node3D] = []
var _body: Node3D
var _crank_angle := 0.0
var _wheel_angle := 0.0
var _lean := 0.0
var _highlight := 0.0
var _trail_segments := 16


func setup(rider_lane: int, jersey: Color, trail_segments: int) -> void:
	lane = rider_lane
	color = jersey
	_trail_segments = maxi(4, trail_segments)
	_build()


func _build() -> void:
	_make_materials()

	_body = Node3D.new()
	_body.name = "Body"
	add_child(_body)

	_build_wheels()
	_build_frame()
	_build_cyclist()
	_build_trail()
	_build_shadow_proxy()


func _make_materials() -> void:
	_jersey_material = ShaderMaterial.new()
	_jersey_material.shader = load("res://art/shaders/jersey.gdshader")
	_jersey_material.set_shader_parameter("jersey_color", color)
	# Très faible : le corps doit être ÉCLAIRÉ, pas lumineux. Un matériau
	# émissif n'a pas d'ombrage, donc toute forme pleine devient un aplat —
	# c'est ce qui donnait des « patates » à la place des cyclistes.
	_jersey_material.set_shader_parameter("emission_energy", 0.22)
	# Liseré plus marqué : c'est lui qui détache la silhouette du parquet, dont
	# la valeur est désormais proche de celle du maillot.
	_jersey_material.set_shader_parameter("rim_energy", 0.85)

	# Jante lumineuse, mais SANS écraser la teinte : au-delà de ~1,2 les canaux
	# saturent l'un après l'autre et la couleur dérive vers le blanc — le vert
	# devenait cyan et l'ambre devenait blanc.
	_rim_material = StandardMaterial3D.new()
	_rim_material.albedo_color = color
	_rim_material.emission_enabled = true
	_rim_material.emission = color
	_rim_material.emission_energy_multiplier = 1.15
	_rim_material.roughness = 0.4

	_frame_material = StandardMaterial3D.new()
	# Assez clair pour PORTER le cycliste : avec un cadre trop sombre, le corps
	# semblait flotter au-dessus de deux anneaux lumineux.
	_frame_material.albedo_color = Color(0.42, 0.47, 0.56)
	_frame_material.roughness = 0.3
	_frame_material.metallic = 0.7
	_frame_material.emission_enabled = true
	_frame_material.emission = color
	_frame_material.emission_energy_multiplier = 0.55


func _build_wheels() -> void:
	for offset: float in [-WHEELBASE_M * 0.5, WHEELBASE_M * 0.5]:
		var wheel := Node3D.new()

		# La jante : un anneau fin et lumineux. C'est le repère visuel qui fait
		# lire « vélo » avant tout le reste.
		var rim := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = WHEEL_RADIUS_M - 0.035
		torus.outer_radius = WHEEL_RADIUS_M
		torus.rings = 24
		torus.ring_segments = 5
		rim.mesh = torus
		rim.material_override = _rim_material
		# `TorusMesh` a son axe sur Y : il est donc À PLAT par défaut. Le tourner
		# autour de Y ne change rien — c'est ce que faisait la première version,
		# d'où des anneaux couchés sur la piste au lieu de roues. Il faut le
		# basculer autour de Z pour mettre l'essieu sur X.
		rim.rotation = Vector3(0.0, 0.0, PI * 0.5)
		wheel.add_child(rim)

		# Quatre bâtons de rayon : ils tournent avec la roue et donnent la
		# rotation, qu'un anneau lisse ne montrerait pas.
		for spoke: int in range(4):
			var bar := MeshInstance3D.new()
			var bar_mesh := BoxMesh.new()
			bar_mesh.size = Vector3(0.014, WHEEL_RADIUS_M * 1.85, 0.014)
			bar.mesh = bar_mesh
			bar.material_override = _frame_material
			bar.rotation = Vector3(float(spoke) * PI / 4.0, 0.0, 0.0)
			wheel.add_child(bar)

		wheel.position = Vector3(0.0, WHEEL_RADIUS_M, offset)
		_body.add_child(wheel)
		_wheels.append(wheel)


func _build_frame() -> void:
	var hub_y := WHEEL_RADIUS_M
	var bracket := Vector3(0.0, hub_y - 0.06, 0.06)
	var saddle := Vector3(0.0, hub_y + 0.50, -0.30)
	var bars := Vector3(0.0, hub_y + 0.44, 0.44)

	# Le triangle du cadre, plus la fourche et la base : cinq tubes suffisent à
	# faire lire un vélo de piste.
	_add_tube(bracket, saddle, 0.035)                                  # tube de selle
	_add_tube(bracket, bars, 0.035)                                    # tube diagonal
	_add_tube(saddle, bars, 0.030)                                     # tube horizontal
	_add_tube(bracket, Vector3(0.0, hub_y, -WHEELBASE_M * 0.5), 0.028)  # base
	_add_tube(bars, Vector3(0.0, hub_y, WHEELBASE_M * 0.5), 0.030)     # fourche

	var handlebar := MeshInstance3D.new()
	var handlebar_mesh := BoxMesh.new()
	handlebar_mesh.size = Vector3(0.40, 0.028, 0.028)
	handlebar.mesh = handlebar_mesh
	handlebar.material_override = _frame_material
	handlebar.position = bars
	_body.add_child(handlebar)

	var seat := MeshInstance3D.new()
	var seat_mesh := BoxMesh.new()
	seat_mesh.size = Vector3(0.07, 0.03, 0.22)
	seat.mesh = seat_mesh
	seat.material_override = _frame_material
	seat.position = saddle + Vector3(0.0, 0.03, 0.0)
	_body.add_child(seat)


## Membre capsulaire entre deux points, orienté le long du segment. Poser les
## membres entre des points du vélo évite les proportions devinées.
func _add_limb(from: Vector3, to: Vector3, radius: float) -> void:
	var span := to - from
	var limb := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = maxf(span.length(), radius * 2.05)
	mesh.radial_segments = 10
	mesh.rings = 3
	limb.mesh = mesh
	limb.material_override = _jersey_material
	limb.position = from + span * 0.5
	var axis := Vector3.UP.cross(span.normalized())
	if axis.length() > 0.0001:
		limb.rotate(axis.normalized(), Vector3.UP.angle_to(span.normalized()))
	_body.add_child(limb)


## Tube cylindrique entre deux points — la brique du cadre.
func _add_tube(from: Vector3, to: Vector3, radius: float) -> void:
	var span := to - from
	var tube := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = span.length()
	mesh.radial_segments = 6
	mesh.rings = 1
	tube.mesh = mesh
	tube.material_override = _frame_material
	tube.position = from + span * 0.5
	# Le cylindre de Godot pointe vers +Y : on l'aligne sur le segment.
	var axis := Vector3.UP.cross(span.normalized())
	if axis.length() > 0.0001:
		tube.rotate(axis.normalized(), Vector3.UP.angle_to(span.normalized()))
	_body.add_child(tube)


## Proportions d'un sprinteur sur un vélo à roues de 0,68 m : bassin sur la
## selle, dos presque horizontal, tête basse et avancée, bras tendus vers le
## guidon. Chaque segment est posé entre DEUX POINTS du vélo plutôt qu'à des
## coordonnées devinées — c'est ce qui garde les proportions justes.
func _build_cyclist() -> void:
	var hub_y := WHEEL_RADIUS_M
	var saddle := Vector3(0.0, hub_y + 0.50, -0.30)
	var bars := Vector3(0.0, hub_y + 0.44, 0.44)

	# Bassin, posé SUR la selle et non au-dessus.
	var hips := saddle + Vector3(0.0, 0.055, 0.02)
	# Épaules : en avant et à peine plus haut, dos presque horizontal.
	var shoulders := Vector3(0.0, hub_y + 0.60, 0.26)

	_add_limb(hips, shoulders, 0.105)  # buste

	# Tête devant les épaules et plus bas : c'est cette avancée qui dit
	# « sprint » et qui détache la tête du buste.
	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.088
	head_mesh.height = 0.185
	head_mesh.radial_segments = 12
	head_mesh.rings = 7
	head.mesh = head_mesh
	head.material_override = _jersey_material
	# Tête basse et avancée : c'est la position de recherche de vitesse.
	head.position = shoulders + Vector3(0.0, -0.01, 0.20)
	_body.add_child(head)

	# Bras : des épaules au guidon, écartés à la largeur des mains. Ils ferment
	# la silhouette et expliquent la position penchée.
	for side: int in [-1, 1]:
		var shoulder := shoulders + Vector3(float(side) * 0.10, -0.02, 0.02)
		var hand := bars + Vector3(float(side) * 0.16, 0.03, 0.0)
		_add_limb(shoulder, hand, 0.046)

	# --- pédalier -----------------------------------------------------------
	_crank = Node3D.new()
	_crank.name = "Crank"
	_crank.position = Vector3(0.0, hub_y - 0.06, 0.06)
	_body.add_child(_crank)

	# Les jambes ne sont PAS accrochées à la manivelle : elles relient la hanche
	# — fixe — au pied, qui tourne avec elle. C'est cette longueur variable qui
	# fait lire un pédalage. Accrochées rigidement, elles traversaient le sol.
	for side: int in [-1, 1]:
		var crank_arm := MeshInstance3D.new()
		var crank_mesh := BoxMesh.new()
		crank_mesh.size = Vector3(0.020, CRANK_LENGTH_M, 0.020)
		crank_arm.mesh = crank_mesh
		crank_arm.material_override = _frame_material
		crank_arm.position = Vector3(float(side) * 0.075, -CRANK_LENGTH_M * 0.5, 0.0)
		# Un demi-tour de décalage entre les deux manivelles.
		var arm_pivot := Node3D.new()
		arm_pivot.rotation.x = 0.0 if side < 0 else PI
		arm_pivot.add_child(crank_arm)
		_crank.add_child(arm_pivot)

		# Hauteur unitaire : la jambe est ÉTIRÉE à la longueur hanche-pédale à
		# chaque image. Une capsule de hauteur fixe laissait des trous aux deux
		# bouts quand la manivelle s'éloignait.
		var leg := MeshInstance3D.new()
		var leg_mesh := CapsuleMesh.new()
		leg_mesh.radius = 0.068
		leg_mesh.height = 1.0
		leg_mesh.radial_segments = 8
		leg_mesh.rings = 3
		leg.mesh = leg_mesh
		leg.material_override = _jersey_material
		_body.add_child(leg)
		_legs.append(leg)


## UNE SEULE OMBRE PAR COUREUR, au lieu d'une par pièce.
##
## Un coureur est fait de vingt-six pièces — jantes, rayons, cadre, membres,
## manivelles. Chacune projetait son ombre, et une lumière directionnelle les
## redessine une fois par cascade : à quatre coureurs, cela faisait plus de
## quatre cents appels de rendu rien que pour les ombres, sur les cinq cents que
## demandait la scène entière. C'est ce coût, multiplié par le nombre de volets,
## qui empêchait l'image d'être fluide.
##
## Les pièces cessent donc de projeter, et un volume approché s'en charge seul,
## invisible dans la passe principale. Sous les néons d'un vélodrome, l'ombre
## d'un coureur est une tache douce : personne n'y lit un rayon de roue.
func _build_shadow_proxy() -> void:
	for node: Node in _body.find_children("*", "GeometryInstance3D", true, false):
		(node as GeometryInstance3D).cast_shadow = \
			GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var proxy := MeshInstance3D.new()
	proxy.name = "ShadowProxy"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.42, 1.05, 1.55)
	proxy.mesh = mesh
	proxy.position = Vector3(0.0, 0.62, 0.0)
	proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	_body.add_child(proxy)


func _build_trail() -> void:
	_trail_material = ShaderMaterial.new()
	_trail_material.shader = load("res://art/shaders/trail.gdshader")
	_trail_material.set_shader_parameter("trail_color", color)

	_trail = MeshInstance3D.new()
	_trail.name = "Trail"
	_trail.material_override = _trail_material
	_trail.mesh = _build_trail_mesh(_trail_segments)
	_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Au ras du sol, derrière la roue arrière : une traînée qui flotte à hauteur
	# de selle ne se lit pas comme une trace de vitesse — c'était le défaut de
	# la première version.
	add_child(_trail)
	_trail.position = Vector3(0.0, 0.0, -WHEELBASE_M * 0.5 - 0.12)


## Aileron VERTICAL effilé, de longueur 1, orienté vers l'arrière. Construit une
## fois ; la vitesse ne fait plus que l'étirer (voir `_update_trail`).
##
## Verticale et non plaquée au sol : à la hauteur de caméra de `docs/04` §4, une
## traînée horizontale est vue en rasant et se réduit à un trait invisible.
## C'était le défaut signalé par l'utilisateur.
static func _build_trail_mesh(segments: int) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	for i: int in range(segments + 1):
		var t := float(i) / float(segments)
		# La hauteur décroît en s'éloignant : une flamme qui se dissipe.
		# Plus basse et plus effilée : une traînée haute masquait la roue
		# arrière et se lisait comme une voile.
		var h := 0.22 * (1.0 - t) * (1.0 - t * 0.5)
		vertices.append(Vector3(0.0, 0.02, -t))
		vertices.append(Vector3(0.0, 0.02 + h, -t))
		uvs.append(Vector2(0.0, 1.0 - t))
		uvs.append(Vector2(1.0, 1.0 - t))
		if i < segments:
			var a := i * 2
			indices.append_array([a, a + 2, a + 1, a + 1, a + 2, a + 3])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Appelée à chaque image. `speed_kph` est la vitesse LISSÉE (docs/01 §7).
func advance(delta: float, speed_kph: float, eliminated: bool, finished: bool) -> void:
	var speed_m_s := speed_kph / 3.6

	# Cadence indexée sur la vitesse réelle : une roue qui tourne trop vite pour
	# l'allure affichée se remarque immédiatement.
	_wheel_angle += speed_m_s / WHEEL_RADIUS_M * delta
	_crank_angle += speed_m_s / WHEEL_RADIUS_M * CRANK_RATIO * delta
	for wheel: Node3D in _wheels:
		wheel.rotation.x = -_wheel_angle
	# MÊME SENS que les roues. Le pédalier tournait à l'endroit pendant que les
	# roues tournaient à l'envers : les jambes pédalaient en marche arrière.
	_crank.rotation.x = -_crank_angle
	_place_legs()

	var target_lean := clampf(speed_m_s / 18.0, 0.0, 1.0) * MAX_LEAN_RAD
	target_lean *= sin(_crank_angle) * 0.5 + 0.5
	_lean = lerpf(_lean, target_lean, clampf(delta * 8.0, 0.0, 1.0))
	_body.rotation.z = _lean

	_highlight = maxf(0.0, _highlight - delta * 2.0)
	_jersey_material.set_shader_parameter("dimmed", 1.0 if eliminated else 0.0)
	_jersey_material.set_shader_parameter("highlight", _highlight)
	_rim_material.emission_energy_multiplier = 0.35 if eliminated else 1.15
	if finished:
		_rim_material.emission_energy_multiplier = 1.6

	_update_trail(speed_kph)


## Replace chaque jambe entre la hanche et sa pédale. Deux transformations par
## image et par rider : aucune géométrie n'est reconstruite.
func _place_legs() -> void:
	var hub_y := WHEEL_RADIUS_M
	var bracket := Vector3(0.0, hub_y - 0.06, 0.06)
	for index: int in range(_legs.size()):
		var side := -1.0 if index == 0 else 1.0
		var phase := -_crank_angle + (0.0 if index == 0 else PI)
		# La pédale décrit un cercle dans le plan de marche.
		var pedal := bracket + Vector3(
			side * 0.075,
			-cos(phase) * CRANK_LENGTH_M,
			sin(phase) * CRANK_LENGTH_M
		)
		var hip := Vector3(side * 0.085, hub_y + 0.50, -0.24)
		var span := pedal - hip
		var length := span.length()
		var leg: MeshInstance3D = _legs[index]
		leg.position = hip + span * 0.5
		leg.rotation = Vector3.ZERO
		# La capsule fait 1 m de haut : on l'étire exactement au segment, sans
		# toucher au maillage.
		leg.scale = Vector3(1.0, maxf(length, 0.2), 1.0)
		var axis := Vector3.UP.cross(span.normalized())
		if axis.length() > 0.0001:
			leg.rotate(axis.normalized(), Vector3.UP.angle_to(span.normalized()))


func flash() -> void:
	_highlight = 1.0


func _update_trail(speed_kph: float) -> void:
	# Longueur ET opacité proportionnelles à la vitesse — docs/04 §4. C'est le
	# principal indice visuel de « ça accélère ».
	var ratio := clampf(speed_kph / 55.0, 0.0, 1.2)
	# Plus longue : c'est la longueur qui traduit la vitesse à l'œil.
	var length := ratio * 9.0
	_trail_material.set_shader_parameter("intensity", clampf(ratio, 0.0, 1.0) * 0.9)
	_trail.visible = length >= 0.3
	if _trail.visible:
		_trail.scale = Vector3(1.0, 1.0, length)
