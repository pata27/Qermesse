## Trois niveaux de qualité et leur détection automatique — docs/04 §4.
##
## Le budget est explicite : **60 fps stables en 1080p sur un GPU intégré**.
## C'est la machine réelle d'un événement, pas une station de jeu. Toute
## fonctionnalité visuelle qui fait passer sous 60 fps est dégradée, pas
## négociée.
##
## `RefCounted` pur : la table des niveaux se lit et se teste sans écran.
class_name RenderQuality
extends RefCounted

enum Level { LOW, MEDIUM, HIGH }

## Effets identifiés comme coûteux par `docs/06` §4 — ce sont les premiers
## coupés quand le budget est dépassé.
const PROFILES := {
	Level.LOW: {
		"name": "bas",
		"crowd_count": 0,
		"volumetric_fog": false,
		"glow": false,
		"speed_lines": false,
		"radial_blur": false,
		"trail_segments": 8,
		"shadows": false,
		"msaa": 0,
		"ssao": false,
	},
	Level.MEDIUM: {
		"name": "moyen",
		"crowd_count": 600,
		"volumetric_fog": false,
		"glow": true,
		"speed_lines": true,
		"radial_blur": false,
		"trail_segments": 16,
		"shadows": true,
		"msaa": 1,
		"ssao": false,
	},
	Level.HIGH: {
		"name": "eleve",
		"crowd_count": 2400,
		"volumetric_fog": true,
		"glow": true,
		"speed_lines": true,
		"radial_blur": true,
		"trail_segments": 32,
		"shadows": true,
		"msaa": 2,
		"ssao": true,
	},
}

static var _override_cache: Variant = null

var level: Level = Level.MEDIUM


func _init(initial: Level = Level.MEDIUM) -> void:
	level = initial


## Détection au premier lancement. Godot expose directement le TYPE d'adaptateur,
## ce qui est bien plus fiable qu'un tableau de noms de cartes à maintenir.
static func detect() -> Level:
	var adapter := RenderingServer.get_video_adapter_type()
	match adapter:
		RenderingDevice.DEVICE_TYPE_DISCRETE_GPU:
			return Level.HIGH
		RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU:
			# La cible de docs/04 §4. On vise « moyen » et on tient 60 fps,
			# plutot que de viser « eleve » et de rater le budget.
			return Level.MEDIUM
		RenderingDevice.DEVICE_TYPE_VIRTUAL_GPU:
			return Level.LOW
		RenderingDevice.DEVICE_TYPE_CPU:
			return Level.LOW
	return Level.MEDIUM


static func adapter_description() -> String:
	return "%s — %s" % [
		RenderingServer.get_video_adapter_name(),
		type_name(RenderingServer.get_video_adapter_type()),
	]


static func type_name(adapter: int) -> String:
	match adapter:
		RenderingDevice.DEVICE_TYPE_DISCRETE_GPU:
			return "GPU dedie"
		RenderingDevice.DEVICE_TYPE_INTEGRATED_GPU:
			return "GPU integre"
		RenderingDevice.DEVICE_TYPE_VIRTUAL_GPU:
			return "GPU virtuel"
		RenderingDevice.DEVICE_TYPE_CPU:
			return "rendu logiciel"
	return "inconnu"


func profile() -> Dictionary:
	return PROFILES[level]


## Surcharges de diagnostic, lues une fois dans `SS_QOPT` sous la forme
## `glow=0,msaa=0,crowd_count=0`. Sert à chiffrer un effet à la fois : sans
## cela, on ne sait pas lequel des six réglages d'un niveau coûte les
## millisecondes qu'on cherche.
static func _overrides() -> Dictionary:
	if _override_cache != null:
		return _override_cache
	var parsed: Dictionary = {}
	for pair: String in OS.get_environment("SS_QOPT").split(",", false):
		var bits := pair.split("=", false)
		if bits.size() == 2:
			parsed[bits[0].strip_edges()] = bits[1].strip_edges()
	_override_cache = parsed
	return parsed


func option(key: String) -> Variant:
	var forced := _overrides()
	if forced.has(key):
		var raw := str(forced[key])
		var current: Variant = profile().get(key)
		if current is bool:
			return raw != "0"
		if current is int:
			return int(raw)
		return raw
	return profile().get(key)


func level_name() -> String:
	return str(profile()["name"])


static func level_from_name(name: String) -> Level:
	for candidate: Level in PROFILES:
		if str(PROFILES[candidate]["name"]) == name:
			return candidate
	return Level.MEDIUM


## Dégrade d'un cran. Appelé par le moniteur de performance quand le budget
## n'est pas tenu : mieux vaut une scène plus sobre qu'une scène qui saccade.
func degrade() -> bool:
	if level == Level.LOW:
		return false
	level = (level - 1) as Level
	return true
