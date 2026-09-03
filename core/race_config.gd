## Parametres d'une course — docs/02.
##
## Objet de donnees pur, sans comportement : il est valide une fois a l'armement
## puis ne bouge plus. Un parametre qui change en cours de course rendrait le
## classement indefendable.
class_name RaceConfig
extends RefCounted

enum Mode { DISTANCE, TIME, PURSUIT }

## docs/02 §4 — defaut AVERTISSEMENT : en evenementiel, relancer une course pour
## un rider qui a bouge enerve le public. RELANCE existe pour le competitif.
enum FalseStartPolicy { IGNORE, WARN, RESTART, PENALTY }

var mode: Mode = Mode.DISTANCE
## Pistes occupees. Les pistes absentes sont ignorees PARTOUT : classement,
## condition de fin, rendu. C'est le correctif du bug historique de la v1.
var active_riders: Array[int] = [0, 1]

var distance_m: float = 500.0  ## mode distance, bornes 50..5000
var duration_s: float = 60.0  ## mode temps, bornes 10..3600
var gap_m: float = 50.0  ## mode poursuite, bornes 10..500

## docs/02 §1 — plafond de securite du mode distance.
var distance_timeout_s: float = 600.0
## docs/02 §3 — plafonds de la poursuite, appliques PAR LE PC : le `t` envoye au
## firmware est inoperant (docs/01 §5.5).
var pursuit_time_cap_s: float = 300.0
var pursuit_distance_cap_m: float = 5000.0

var false_start_policy: FalseStartPolicy = FalseStartPolicy.WARN
var false_start_penalty_m: float = 10.0

var roller_mm: float = Physics.DEFAULT_ROLLER_MM
## Fenetre de lissage de la vitesse MESUREE, en echantillons — docs/01 §7.
## Vingt (~200 ms a 100 Hz) : la v1 lissait sur soixante, trop mou pour un rendu
## de jeu ; la v2 sur dix, trop nerveux. Reglage avance, fige a l'armement comme
## le reste : une fenetre qui changerait en cours de course rendrait deux
## vitesses de la meme course incomparables.
var speed_samples: int = Physics.SPEED_SAMPLES


## Rend une liste de problemes. Vide si la configuration est jouable.
func validate() -> Array[String]:
	var problems: Array[String] = []
	if active_riders.is_empty():
		problems.append("aucune piste active : il faut au moins un rider")
	for rider: int in active_riders:
		if rider < 0 or rider >= Protocol.MAX_RIDERS:
			# INDICE, et le mot le dit. Partout ailleurs « piste N » designe le
			# numero HUMAIN, 1..4 ; ici la valeur est justement hors de cette
			# plage — elle ne peut venir que d'un fichier edite a la main — et la
			# nommer « piste » la ferait lire comme un numero de couloir.
			problems.append("indice de piste %d hors bornes 0..3" % rider)
	if active_riders.size() != _unique(active_riders).size():
		problems.append("une piste est déclarée deux fois")
	if roller_mm <= 0.0:
		problems.append("diamètre de rouleau invalide : %.1f mm" % roller_mm)
	if speed_samples < 1 or speed_samples > 240:
		problems.append("fenetre de lissage %d hors bornes 1..240" % speed_samples)

	match mode:
		Mode.DISTANCE:
			if distance_m < 50.0 or distance_m > 5000.0:
				problems.append("distance %.0f m hors bornes 50..5000" % distance_m)
			# La distance doit se traduire en une commande `l` acceptable par le
			# firmware — docs/01 §2.
			var ticks := Physics.new(roller_mm).metres_to_ticks(distance_m)
			if not Protocol.is_valid_firmware_argument(ticks):
				problems.append("%.0f m font %d ticks, hors bornes firmware" % [distance_m, ticks])
		Mode.TIME:
			if duration_s < 10.0 or duration_s > 3600.0:
				problems.append("durée %.0f s hors bornes 10..3600" % duration_s)
		Mode.PURSUIT:
			if gap_m < 10.0 or gap_m > 500.0:
				problems.append("écart %.0f m hors bornes 10..500" % gap_m)
			if active_riders.size() < 2:
				problems.append("la poursuite exige au moins deux riders")
			# UNE PENALITE QUI VAUT L'ECART TERMINE LA COURSE AVANT LE DEPART.
			# Le fautif part `P` metres en arriere ; si `P` atteint l'ecart
			# decisif, il est elimine a la premiere trame — course finie en onze
			# millisecondes, vainqueur a 0,0 m et 0,0 km/h. L'operateur doit
			# l'apprendre a l'armement, pas devant le public.
			if (
				false_start_policy == FalseStartPolicy.PENALTY
				and false_start_penalty_m >= gap_m
			):
				problems.append(
					"pénalité de %.0f m pour un écart décisif de %.0f m : un faux départ"
					% [false_start_penalty_m, gap_m]
					+ " éliminerait le fautif avant qu'il ait pédalé"
				)
	return problems


func is_valid() -> bool:
	return validate().is_empty()


## Sequence serie a emettre pour armer cette course — docs/01 §2 et §5.5.
## L'ordre est impose : `d`/`x`, puis `l`/`t`, puis `g`.
func arming_commands() -> Array[String]:
	if mode == Mode.DISTANCE:
		var ticks := Physics.new(roller_mm).metres_to_ticks(distance_m)
		return ["d", "l%d" % ticks, "g"]
	# Temps ET poursuite passent par le mode temps du firmware, avec la
	# constante sure t60 : la vraie duree est arbitree par le PC.
	return ["x", Protocol.TIME_COMMAND, "g"]


## Nom d'un mode et son inverse. Les fichiers ecrivent des NOMS, pas des
## entiers : `"mode": 2` ne dit rien a qui ouvre le fichier, et `DEPANNAGE`
## en donne le chemin a l'operateur. La trace d'une course le faisait deja ;
## les reglages le font aussi, et la conversion vit ici plutot qu'en deux
## exemplaires.
static func mode_from_name(name: String, fallback: Mode = Mode.DISTANCE) -> Mode:
	match name:
		"distance":
			return Mode.DISTANCE
		"temps":
			return Mode.TIME
		"poursuite":
			return Mode.PURSUIT
	return fallback


static func policy_name(value: FalseStartPolicy) -> String:
	match value:
		FalseStartPolicy.IGNORE:
			return "ignorer"
		FalseStartPolicy.WARN:
			return "avertissement"
		FalseStartPolicy.RESTART:
			return "relance"
		FalseStartPolicy.PENALTY:
			return "penalite"
	return "avertissement"


static func policy_from_name(
	name: String, fallback: FalseStartPolicy = FalseStartPolicy.WARN
) -> FalseStartPolicy:
	match name:
		"ignorer":
			return FalseStartPolicy.IGNORE
		"avertissement":
			return FalseStartPolicy.WARN
		"relance":
			return FalseStartPolicy.RESTART
		"penalite":
			return FalseStartPolicy.PENALTY
	return fallback


static func mode_name_of(value: Mode) -> String:
	match value:
		Mode.DISTANCE:
			return "distance"
		Mode.TIME:
			return "temps"
		Mode.PURSUIT:
			return "poursuite"
	return "distance"


func mode_name() -> String:
	return mode_name_of(mode)


func duplicate_config() -> RaceConfig:
	var copy := RaceConfig.new()
	copy.mode = mode
	copy.active_riders = active_riders.duplicate()
	copy.distance_m = distance_m
	copy.duration_s = duration_s
	copy.gap_m = gap_m
	copy.distance_timeout_s = distance_timeout_s
	copy.pursuit_time_cap_s = pursuit_time_cap_s
	copy.pursuit_distance_cap_m = pursuit_distance_cap_m
	copy.false_start_policy = false_start_policy
	copy.false_start_penalty_m = false_start_penalty_m
	copy.roller_mm = roller_mm
	copy.speed_samples = speed_samples
	return copy


func _unique(values: Array[int]) -> Array[int]:
	var seen: Array[int] = []
	for v: int in values:
		if not seen.has(v):
			seen.append(v)
	return seen
