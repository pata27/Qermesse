## Écran scindé à N volets — autant de volets que la course a de paquets.
##
## **Le problème.** Cadrer tout le monde devient impossible passé une dizaine de
## mètres : la caméra recule et les coureurs deviennent des points. Toute
## retransmission résout cela en scindant l'image.
##
## **Combien de volets.** Autant que de paquets, jusqu'à quatre. La course est
## découpée à chaque écart qui dépasse le seuil ; un peloton qui casse en 2 + 2
## donne deux volets, une échappée solo suivie d'un trio en donne deux aussi
## mais de tailles différentes, et quatre coureurs qui s'égrènent en donnent
## quatre. Le nombre de volets suit la course, pas le nombre de pistes.
##
## **L'architecture.** Le groupe de tête est rendu directement dans la fenêtre —
## il ne coûte rien de plus. Chaque groupe suivant passe par un `SubViewport`
## composé par-dessus au moyen d'une lame animée. Les lames se superposent de
## gauche à droite : la lame `p` recouvre tout ce qui se trouve à sa droite, si
## bien qu'empiler les volets dans l'ordre suffit à les découper — aucun masque,
## aucune recopie du tampon d'écran.
class_name SplitScreen
extends Node

signal opened()
signal closed()

## Quatre groupes au plus, donc trois lames. Au-delà, il n'y a plus de coureur
## à mettre dedans : la piste en compte quatre.
const MAX_PANES := 3
## Seuils asymétriques : sans hystérésis, un écart qui oscille autour du seuil
## ferait clignoter la séparation en permanence. Appliqués séparément à CHAQUE
## cassure, sinon l'ouverture du troisième volet ferait vaciller le second.
## SIX MÈTRES, et non quatorze. La caméra ne sait cadrer qu'une quinzaine de
## mètres d'étalement (`CameraRig.MAX_FRAMED_SPREAD_M`) : attendre quatorze
## mètres pour scinder, c'était scinder au moment précis où le retardataire
## venait de sortir du champ. Il faut couper AVANT que le cadre ne lâche, pas
## après.
const OPEN_ABOVE_M := 6.0
const CLOSE_BELOW_M := 4.0
## Durée d'ouverture d'une lame. Assez lente pour se lire comme un mouvement,
## assez rapide pour ne pas faire attendre.
const TRANSITION_S := 0.85
## Décalage entre deux lames qui s'ouvrent en même temps : elles entrent l'une
## après l'autre, ce qui se lit comme une suite de coupes et non comme un store.
const STAGGER_S := 0.14
## Vitesse à laquelle une lame glisse vers sa nouvelle place quand le nombre de
## volets change. Une lame qui saute de la moitié au tiers casse l'illusion.
const SLIDE_RATE := 3.0
## Marge de part et d'autre de la lame, en fraction de largeur d'écran. Doit
## couvrir l'excursion horizontale de la lame due à son inclinaison — elle
## déplace sa trace de `slant/2` entre le haut et le bas de l'image — et le
## halo lumineux qui la borde.
const SLICE_MARGIN := 0.16


## Un volet : sa vue, sa caméra, sa lame.
class Pane:
	var index := 0
	var viewport: SubViewport
	var rig: CameraRig
	var composite: ColorRect
	var material: ShaderMaterial
	var amount := 0.0
	var target := 0.0
	var elapsed := 0.0
	var delay := 0.0
	var line := 1.0
	var line_target := 0.5
	var visible_now := false


var _world: World3D
var _size := Vector2i(1920, 1080)
var _layer: CanvasLayer
var _panes: Array[Pane] = []
var _warm_frames := 0
var _cuts: Array[bool] = []
var _live_panes := 0


func setup(world: World3D, size: Vector2i) -> void:
	_world = world
	if size.x > 0 and size.y > 0:
		_size = size
	_layer = CanvasLayer.new()
	_layer.layer = 1
	add_child(_layer)


## Réserve d'avance les volets qu'une course à `riders` coureurs pourra ouvrir,
## et les fait dessiner quelques images pour compiler leur shader.
##
## Alloués au moment où ils s'ouvrent, ils coûtaient une cible de rendu en
## 1080p et une compilation de shader EN PLEINE COURSE : la mesure montrait un
## 1 % bas à 48 fps et un minimum à 23,6 pour une moyenne de 149. Un peloton qui
## casse est précisément le moment où l'image ne doit pas hoqueter.
##
## Le nombre est borné par la course : à deux coureurs, une seule cassure est
## possible, donc un seul volet à réserver.
func prime(riders: int) -> void:
	for index: int in range(maxi(riders - 1, 0)):
		var pane := _ensure_pane(index)
		# Dessiné quelques images à ouverture nulle : la lame est alors hors
		# cadre et le volet entièrement transparent, mais Godot compile le
		# shader — ce qu'il ne ferait pas sur un noeud caché.
		pane.material.set_shader_parameter("split_amount", 0.0)
		pane.composite.visible = true
		# Et RENDUE une fois : allouer la cible ne suffit pas, c'est le premier
		# rendu qui construit les tampons et les pipelines propres à cette vue.
		pane.viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_warm_frames = 3


## Crée un volet au premier besoin.
func _ensure_pane(index: int) -> Pane:
	while _panes.size() <= index:
		var pane := Pane.new()
		pane.index = _panes.size()

		pane.viewport = SubViewport.new()
		pane.viewport.name = "GroupView%d" % _panes.size()
		pane.viewport.size = _slice_size(_panes.size())
		pane.viewport.world_3d = _world
		pane.viewport.own_world_3d = false
		pane.viewport.transparent_bg = false
		# PLEINE RÉSOLUTION ET ANTICRÉNELAGE. Rendues en demi-résolution puis
		# étirées, ces vues faisaient fourmiller les néons — des traits d'un
		# pixel de large ne supportent aucun rééchantillonnage.
		pane.viewport.msaa_3d = Viewport.MSAA_2X
		# Tant que la lame est fermée, la vue n'est pas dessinée : une caméra
		# qui tourne pour rien coûterait sa part entière du budget.
		pane.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(pane.viewport)

		pane.rig = CameraRig.new()
		pane.rig.name = "GroupRig%d" % _panes.size()
		pane.viewport.add_child(pane.rig)

		pane.material = ShaderMaterial.new()
		pane.material.shader = load("res://art/shaders/split.gdshader")
		pane.material.set_shader_parameter("other_view", pane.viewport.get_texture())

		pane.composite = ColorRect.new()
		pane.composite.name = "SplitComposite%d" % _panes.size()
		pane.composite.material = pane.material
		pane.composite.set_anchors_preset(Control.PRESET_FULL_RECT)
		pane.composite.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pane.composite.visible = false
		# L'ordre d'ajout EST l'ordre de dessin : la lame `p` recouvre tout ce
		# qui est à sa droite, donc les volets doivent s'empiler de gauche à
		# droite pour se découper mutuellement.
		_layer.add_child(pane.composite)

		_panes.append(pane)
	return _panes[index]


## Décide, cassure par cassure, lesquelles méritent une lame.
##
## `gaps[i]` est l'écart entre le i-ème et le (i+1)-ème coureur, classés du
## premier au dernier. Une cassure déjà ouverte ne se referme qu'en dessous du
## seuil bas : c'est l'hystérésis, sans laquelle un écart qui oscille autour du
## seuil ferait battre la lame.
func consider(gaps: PackedFloat32Array) -> void:
	var was_open := _live_panes > 0

	var cuts: Array[bool] = []
	for index: int in range(gaps.size()):
		var previously: bool = index < _cuts.size() and _cuts[index]
		var threshold := CLOSE_BELOW_M if previously else OPEN_ABOVE_M
		cuts.append(gaps[index] > threshold)
	_cuts = cuts

	var open_cuts := 0
	for cut: bool in _cuts:
		if cut:
			open_cuts += 1
	_live_panes = mini(open_cuts, MAX_PANES)

	# Les lames se répartissent en parts égales de la largeur. Quand une
	# quatrième apparaît, les précédentes glissent vers leur nouvelle place au
	# lieu d'y sauter — c'est `SLIDE_RATE` qui s'en charge dans `advance`.
	var slices := float(_live_panes + 1)
	for index: int in range(_live_panes):
		var pane := _ensure_pane(index)
		pane.line_target = float(index + 1) / slices
		if pane.target == 0.0:
			pane.elapsed = 0.0
			if index > 0 and _panes[index - 1].amount > 0.0:
				# UNE LAME QUI NAÎT AU MILIEU SORT DE SA VOISINE.
				#
				# Un groupe de trois qui casse en 2 + 1 pendant la course
				# insère une cassure À GAUCHE de celles déjà ouvertes : les
				# volets existants glissent tous d'un cran vers la droite. Si
				# la nouvelle lame entrait depuis le bord droit comme une
				# première ouverture, le coureur qu'elle doit encadrer restait
				# invisible le temps qu'elle traverse l'écran.
				#
				# Elle démarre donc à la place de sa voisine et dans le même
				# état d'ouverture, puis les deux glissent vers leurs nouvelles
				# parts : la lame se dédouble, ce qui est exactement ce que
				# raconte la course.
				pane.line = _panes[index - 1].line
				pane.amount = _panes[index - 1].amount
				pane.delay = 0.0
			else:
				pane.delay = float(index) * STAGGER_S
		pane.target = 1.0
	for index: int in range(_live_panes, _panes.size()):
		_panes[index].target = 0.0

	if _live_panes > 0 and not was_open:
		opened.emit()
	elif _live_panes == 0 and was_open:
		closed.emit()


func advance(delta: float) -> void:
	if _warm_frames > 0:
		_warm_frames -= 1
		if _warm_frames == 0:
			for pane: Pane in _panes:
				if not pane.visible_now:
					pane.composite.visible = false

	for pane: Pane in _panes:
		var step := delta / TRANSITION_S
		if pane.target > 0.0:
			pane.elapsed += delta
			if pane.elapsed < pane.delay:
				step = 0.0
		pane.amount = move_toward(pane.amount, pane.target, step)

		if pane.amount <= 0.0 and pane.target == 0.0:
			if pane.visible_now:
				pane.visible_now = false
				pane.composite.visible = false
				pane.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
				# La lame repart de la droite au prochain coup : sans cela elle
				# réapparaîtrait en place, sans mouvement d'entrée.
				pane.line = 1.0
			continue

		if not pane.visible_now:
			pane.visible_now = true
			pane.composite.visible = true
			pane.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			# Une seule image de placement immédiat : sans elle, la caméra du
			# volet arriverait en volant depuis l'origine du monde. Ensuite
			# l'amortissement reprend.
			pane.rig.request_snap()

		# La lame glisse vers sa part de largeur. Amortissement indépendant du
		# framerate : même mouvement à 60 et à 144 images par seconde.
		pane.line = lerpf(
			pane.line, pane.line_target, 1.0 - exp(-SLIDE_RATE * delta)
		)

		# Adoucissement en entrée ET en sortie : une interpolation linéaire
		# donne un volet mécanique, la courbe donne un mouvement.
		var eased: float = pane.amount * pane.amount * (3.0 - 2.0 * pane.amount)
		pane.material.set_shader_parameter("split_amount", eased)
		pane.material.set_shader_parameter("line_pos", pane.line)
		# La lame s'incline un peu plus au plus fort du mouvement : c'est ce
		# frémissement qui fait qu'elle semble découper l'image plutôt que
		# glisser par-dessus.
		pane.material.set_shader_parameter("slant", 0.14 + sin(eased * PI) * 0.06)
		# La vue ne couvre que sa tranche : le composite doit savoir où elle
		# commence et quelle largeur elle représente, sinon il l'échantillonne
		# comme une image plein cadre et tout est décalé.
		var left: float = pane.line - SLICE_MARGIN
		pane.material.set_shader_parameter("slice_u0", left)
		pane.material.set_shader_parameter("slice_w", _slice_width(pane.index))


## Cassures retenues, dans l'ordre du peloton. La scène s'en sert pour découper
## les coureurs exactement comme l'image est découpée.
func cuts() -> Array[bool]:
	return _cuts


## Taille en pixels de la vue d'un volet : sa tranche de largeur, toute la
## hauteur.
func _slice_size(pane_index: int) -> Vector2i:
	return Vector2i(
		maxi(int(round(float(_size.x) * _slice_width(pane_index))), 16), _size.y
	)


## Nombre de groupes actuellement montrés — un de plus que le nombre de lames.
func group_count() -> int:
	return _live_panes + 1


## Caméra du groupe `group`. Le groupe 0 est rendu par la caméra principale de
## la scène, qui n'appartient pas à ce composant ; d'où le décalage.
func rig(group: int) -> CameraRig:
	if group <= 0 or group > _panes.size():
		return null
	return _panes[group - 1].rig


## Décadrage à appliquer à la caméra du groupe `group` pour qu'il tombe au
## milieu de SON volet et non au milieu de l'écran. Suit l'animation : le sujet
## glisse vers sa place pendant que la lame entre, il n'y saute pas.
## Cadrage du groupe `group` : où placer le sujet à l'écran, et quelle tranche
## d'écran sa vue doit rendre. Rendu sous la forme
## `Vector3(sujet, bord_gauche, bord_droit)`, en fractions de largeur d'écran.
##
## Le sujet vise le milieu de SON volet, et y glisse au rythme de l'ouverture :
## il ne saute pas à sa place quand la lame entre.
##
## Le groupe de tête est rendu directement dans la fenêtre : sa tranche est
## l'écran entier. Les autres ne rendent que leur bande.
func window_for(group: int) -> Vector3:
	var slices := float(group_count())
	var subject := lerpf(0.5, (float(group) + 0.5) / slices, openness())
	if group <= 0 or group > _panes.size():
		return Vector3(subject, 0.0, 1.0)
	var pane := _panes[group - 1]
	var left := pane.line - SLICE_MARGIN
	return Vector3(subject, left, left + _slice_width(pane.index))


## Part de la largeur d'écran qu'un volet doit rendre.
##
## Fixée une fois pour toutes, car changer la taille d'une cible de rendu la
## réalloue — et une réallocation en pleine course, c'est le hoquet qu'on vient
## de supprimer. Elle est donc dimensionnée pour le PIRE cas de ce volet : sa
## bande est la plus large quand il est le dernier ouvert, où elle va de sa lame
## au bord droit de l'écran, soit `1/(p+2)`. La marge couvre l'inclinaison de la
## lame, qui déplace sa trace horizontale de `slant/2` sur la hauteur, et le
## halo qui la borde.
static func _slice_width(pane_index: int) -> float:
	return 1.0 / float(pane_index + 2) + 2.0 * SLICE_MARGIN


## Avancement global de l'animation, pour tout ce qui doit suivre l'ouverture.
func openness() -> float:
	var top := 0.0
	for pane: Pane in _panes:
		top = maxf(top, pane.amount)
	return top


func is_open() -> bool:
	return _live_panes > 0


func amount() -> float:
	return openness()


## Suit la taille de la fenêtre : une texture figée puis étirée fourmillait.
func resize(size: Vector2i) -> void:
	if size.x <= 0 or size.y <= 0:
		return
	_size = size
	for index: int in range(_panes.size()):
		_panes[index].viewport.size = _slice_size(index)
