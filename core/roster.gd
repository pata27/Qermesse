## Roster des riders — docs/03 §2 et docs/02 §5.
##
## Les noms sont PERSISTES : la v1 les perdait a chaque lancement, ce qui
## obligeait a les ressaisir entre deux manches d'une meme soiree.
##
## Une piste est identifiee par sa couleur ET son numero (docs/03 §6) : aucune
## information ne doit reposer sur la seule couleur.
class_name Roster
extends RefCounted

## docs/04 §2 — palette figee, une couleur par piste.
const DEFAULT_COLORS := ["#00E5FF", "#FF2E88", "#FFB300", "#00E676"]

## Longueur AFFICHABLE d'un nom, en caracteres.
##
## La carte de l'ecran public donne 414 px au nom avant le compteur de vitesse,
## a la police 34 : une vingtaine de caracteres. Au-dela, le nom passait
## par-dessus le compteur et debordait sur la scene, et la colonne `nom` du
## tableau operateur — a largeur fixe — poussait toute la ligne vers la droite.
## La donnee stockee, elle, n'est jamais amputee : c'est l'AFFICHAGE qui borne.
const MAX_DISPLAY_NAME := 18
## Un dossard tient en quelques caracteres ; la colonne du tableau en fait cinq.
const MAX_DOSSARD := 6


## Ramene un nom a la largeur affichable, en montrant qu'il est coupe. Point
## de passage unique : la carte, le podium et le tableau y viennent tous.
static func shorten(name: String) -> String:
	if name.length() <= MAX_DISPLAY_NAME:
		return name
	return "%s…" % name.substr(0, MAX_DISPLAY_NAME - 1)


class Rider:
	extends RefCounted
	var lane: int = 0
	var name: String = ""
	var dossard: String = ""
	var color: String = "#FFFFFF"
	var active: bool = false

	func display_name() -> String:
		# Un rider sans nom reste identifiable : on ne laisse jamais une ligne
		# vide a l'ecran spectacle.
		return Roster.shorten(name) if not name.is_empty() else "Piste %d" % (lane + 1)

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


## Pour le CSV : {lane: {name, dossard}} — docs/02 §5.
func to_recorder_map() -> Dictionary:
	var out := {}
	for entry: Rider in riders:
		if entry.active:
			out[entry.lane] = {"name": entry.display_name(), "dossard": entry.dossard}
	return out


func to_dict() -> Dictionary:
	var list: Array = []
	for entry: Rider in riders:
		list.append(entry.to_dict())
	return {"riders": list}


func from_dict(data: Dictionary) -> void:
	var list: Array = data.get("riders", [])
	for item: Variant in list:
		if not (item is Dictionary):
			continue
		var loaded := Rider.from_dict(item)
		var target := rider(loaded.lane)
		if target != null:
			target.name = loaded.name
			target.dossard = loaded.dossard
			target.color = loaded.color
			target.active = loaded.active


func save(path: String = "") -> bool:
	return JsonStore.write(path if not path.is_empty() else AppPaths.roster_path(), to_dict())


func load_from(path: String = "") -> bool:
	var data := JsonStore.read(path if not path.is_empty() else AppPaths.roster_path())
	if data.is_empty():
		return false
	from_dict(data)
	return true
