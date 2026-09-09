## Roster des riders — docs/03 §2 et docs/02 §5.
##
## Les noms sont PERSISTES : la v1 les perdait a chaque lancement, ce qui
## obligeait a les ressaisir entre deux manches d'une meme soiree.
##
## Une piste est identifiee par sa couleur ET son numero (docs/03 §6) : aucune
## information ne doit reposer sur la seule couleur.
class_name Roster
extends RefCounted

## docs/04 §2 — couleur PAR DEFAUT de chaque piste. L'operateur peut la changer
## pour coller aux velos reellement poses sur les rouleaux, et y revenir.
const DEFAULT_COLORS := ["#00E5FF", "#FF2E88", "#FFB300", "#00E676"]
## Ecart en dessous duquel deux couleurs se confondent a la projection. Les
## teintes par defaut sont a plus de 0,6 l'une de l'autre ; deux rouges choisis
## a la main tombent bien en dessous.
const COLOR_CLASH := 0.25

## Longueur AFFICHABLE d'un nom, en caracteres.
##
## La carte de l'ecran public donne 414 px au nom avant le compteur de vitesse,
## a la police 34 : une vingtaine de caracteres. Au-dela, le nom passait
## par-dessus le compteur et debordait sur la scene, et la colonne `nom` du
## tableau operateur — a largeur fixe — poussait toute la ligne vers la droite.
## La donnee stockee, elle, n'est jamais amputee : c'est l'AFFICHAGE qui borne.
const MAX_DISPLAY_NAME := 18
## Un dossard tient en quelques caracteres ; la colonne du tableau de resultats
## en fait six, et n'apparait que si au moins une piste en porte un.
const MAX_DOSSARD := 6


class Rider:
	extends RefCounted
	var lane: int = 0
	var name: String = ""
	var dossard: String = ""
	var color: String = "#FFFFFF"
	var active: bool = false

	## Le nom ENTIER, tel qu'il sera ecrit dans les fichiers : ce que
	## l'operateur a saisi, ou « Piste N » s'il n'a rien saisi — un fichier
	## doit se lire seul, sans connaitre la convention d'affichage.
	func full_name() -> String:
		return name if not name.is_empty() else "Piste %d" % (lane + 1)


	## Le meme, borne a ce qu'un ecran peut montrer. La troncature est un
	## effet d'AFFICHAGE : elle se compose par-dessus, elle ne remplace pas.
	func display_name() -> String:
		return Roster.shorten(full_name())

	func to_dict() -> Dictionary:
		return {
			"lane": lane, "name": name, "dossard": dossard, "color": color, "active": active
		}

	static func from_dict(data: Dictionary) -> Rider:
		var rider := Rider.new()
		rider.lane = int(data.get("lane", 0))
		rider.name = str(data.get("name", ""))
		rider.dossard = str(data.get("dossard", ""))
		rider.color = str(data.get("color", "#FFFFFF"))
		rider.active = bool(data.get("active", false))
		return rider

var riders: Array[Rider] = []
## CE QUE LE CHARGEMENT A CORRIGE, une entree par valeur — meme regle que les
## reglages : ramener a la charte sans le dire, c'est changer la couleur d'un
## velo sous les pieds de l'operateur qui a edite le fichier a la main.
var _corrections: Array[String] = []


## Ramene un nom a la largeur affichable, en montrant qu'il est coupe. Point
## de passage unique : la carte, le podium et le tableau y viennent tous.
static func shorten(name: String) -> String:
	if name.length() <= MAX_DISPLAY_NAME:
		return name
	return "%s…" % name.substr(0, MAX_DISPLAY_NAME - 1)


func _init() -> void:
	for lane: int in range(Protocol.MAX_RIDERS):
		var rider := Rider.new()
		rider.lane = lane
		rider.color = DEFAULT_COLORS[lane]
		# Le boitier de l'utilisateur a deux capteurs cables : on part sur deux
		# pistes actives, la configuration la plus courante.
		rider.active = lane < 2
		riders.append(rider)


func rider(lane: int) -> Rider:
	return riders[lane] if lane >= 0 and lane < riders.size() else null


func active_lanes() -> Array[int]:
	var out: Array[int] = []
	for entry: Rider in riders:
		if entry.active:
			out.append(entry.lane)
	return out


func set_active(lane: int, active: bool) -> void:
	var entry := rider(lane)
	if entry != null:
		entry.active = active


## Couleur choisie pour une piste. Refuse ce qui n'est pas une couleur : le
## point d'entree est unique, la validation aussi.
func set_color(lane: int, color: String) -> bool:
	var entry := rider(lane)
	if entry == null or not Color.html_is_valid(color):
		return false
	entry.color = color
	return true


## Rend une piste a sa couleur de charte — docs/04 §2. Le seul geste utile
## quand la salle change de velos entre deux soirees.
func reset_color(lane: int) -> void:
	var entry := rider(lane)
	if entry != null:
		entry.color = DEFAULT_COLORS[lane]


## Pistes ACTIVES dont la couleur se confond avec celle d'une autre.
##
## Signale, n'interdit pas — docs/04 §2. Si la salle aligne deux velos rouges,
## l'operateur a raison contre la charte et le logiciel n'a pas a reecrire la
## realite ; le numero de piste et le nom identifient chacun. Mais un doublon
## involontaire rend l'ecran ambigu, et cela se dit.
func clashing_lanes() -> Array[int]:
	var clashing: Array[int] = []
	var lanes := active_lanes()
	for a: int in lanes:
		for b: int in lanes:
			if a == b or clashing.has(a):
				continue
			var distance := Color(rider(a).color) - Color(rider(b).color)
			var gap := absf(distance.r) + absf(distance.g) + absf(distance.b)
			if gap < COLOR_CLASH:
				clashing.append(a)
	clashing.sort()
	return clashing


## Pour le CSV : {lane: {name, dossard}} — docs/02 §5.
## Ce que le recorder ecrit au disque : le nom ENTIER.
##
## Cette fonction passait par `display_name()`, qui borne a la largeur
## affichable depuis qu'un nom long debordait de sa carte. Consequence non
## voulue : le nom ECRIT dans le CSV et le JSON etait ampute, points de
## suspension compris. C'est l'affichage qui borne, jamais la donnee.
func to_recorder_map() -> Dictionary:
	var out := {}
	for entry: Rider in riders:
		if entry.active:
			out[entry.lane] = {"name": entry.full_name(), "dossard": entry.dossard}
	return out


func to_dict() -> Dictionary:
	var list: Array = []
	for entry: Rider in riders:
		list.append(entry.to_dict())
	return {"riders": list}


func from_dict(data: Dictionary) -> void:
	_corrections.clear()
	var list: Array = data.get("riders", [])
	for item: Variant in list:
		if not (item is Dictionary):
			continue
		var loaded := Rider.from_dict(item)
		var target := rider(loaded.lane)
		if target == null:
			_corrections.append(
				"piste %d hors 1..%d, entrée ignorée" % [loaded.lane + 1, Protocol.MAX_RIDERS]
			)
			continue
		if target != null:
			target.name = loaded.name
			target.dossard = loaded.dossard
			target.active = loaded.active
			# LA COULEUR SE RELIT, MAIS SOUS CONDITION. Elle ne venait pas du
			# fichier tant que la palette etait figee ; elle se regle desormais,
			# donc elle se retrouve au lancement suivant comme les noms.
			#
			# Validee, en revanche. Un roster edite a la main — ou ecrit par une
			# version future — peut porter n'importe quoi, et une teinte
			# illisible sur l'ecran public ne se decouvrirait qu'en soiree. Une
			# couleur invalide rend donc la piste a son defaut, qui est toujours
			# lisible.
			if Color.html_is_valid(loaded.color):
				target.color = loaded.color
			else:
				_corrections.append(
					"piste %d : couleur « %s » invalide, couleur de charte gardée"
					% [loaded.lane + 1, loaded.color]
				)


## Les corrections du dernier chargement, pour la ligne de demarrage.
func corrections() -> Array[String]:
	return _corrections


func save(path: String = "") -> bool:
	return JsonStore.write(path if not path.is_empty() else AppPaths.roster_path(), to_dict())


func load_from(path: String = "") -> bool:
	var data := JsonStore.read(path if not path.is_empty() else AppPaths.roster_path())
	if data.is_empty():
		return false
	from_dict(data)
	return true
