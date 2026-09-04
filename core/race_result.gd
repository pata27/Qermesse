## Resultat fige d'une course — ce que `recorder.gd` ecrit et ce que l'ecran de
## resultats affiche. Aucune logique : une fois construit, il ne change plus.
class_name RaceResult
extends RefCounted

var uuid: String = ""
var started_at_iso: String = ""
var finished_at_iso: String = ""
var mode: String = ""
var config: RaceConfig = null

## Du premier au dernier. Contient uniquement des pistes ACTIVES.
var ranking: Array[int] = []
var elapsed_ms: int = 0
var end_reason: RaceRule.EndReason = RaceRule.EndReason.NONE
## Course coupee avant son terme : plafond de securite, abandon operateur, ou
## lien perdu au-dela du delai de grace. Le resultat reste exploitable mais
## doit etre signale comme tel — docs/02 §5.
var interrupted: bool = false
var interruption_note: String = ""

## Par piste, indexe 0..3. Les pistes inactives restent a zero.
var finished_ms: PackedInt32Array = PackedInt32Array()
var distance_m: PackedFloat32Array = PackedFloat32Array()
var avg_kph: PackedFloat32Array = PackedFloat32Array()
var max_kph: PackedFloat32Array = PackedFloat32Array()
var eliminated: Array[bool] = []
## Instant de l'elimination en ms, 0 sinon — voir `RaceState.eliminated_ms`.
var eliminated_ms: PackedInt32Array = PackedInt32Array()
var false_started: Array[bool] = []
## Noms des riders TELS QU'AU DEPART, piste -> nom. L'ecran de resultats et
## l'historique lisent ceux-la, jamais le roster courant : renommer les pistes
## entre deux courses ne reecrit pas l'histoire — docs/02 §5.
var rider_names: Dictionary = {}
## Dossards TELS QU'AU DEPART, piste -> dossard. Meme regle que les noms, et
## pour la meme raison : l'operateur les saisit avant la course et peut les
## changer entre deux manches. Sans capture, le tableau de resultats
## reetiquetterait une course passee avec les numeros de la suivante.
var rider_dossards: Dictionary = {}


func _init() -> void:
	finished_ms.resize(Protocol.MAX_RIDERS)
	eliminated_ms.resize(Protocol.MAX_RIDERS)
	distance_m.resize(Protocol.MAX_RIDERS)
	avg_kph.resize(Protocol.MAX_RIDERS)
	max_kph.resize(Protocol.MAX_RIDERS)
	for i: int in range(Protocol.MAX_RIDERS):
		eliminated.append(false)
		false_started.append(false)


## L'heure d'arrivee « HH:MM » en heure LOCALE — les fichiers sont en UTC,
## l'operateur lit l'heure de la salle.
func finished_at_local() -> String:
	if finished_at_iso.length() < 19:
		return ""
	var unix := Time.get_unix_time_from_datetime_string(finished_at_iso)
	unix += int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var local := Time.get_datetime_dict_from_unix_time(unix)
	return "%02d:%02d" % [int(local["hour"]), int(local["minute"])]


## La course a-t-elle ete ARRETEE, ou seulement decidee autrement ?
##
## `interrupted` couvre deux situations que rien ne separait a l'affichage, et
## la confusion a ete corrigee ecran par ecran, trois fois, avant d'etre nommee
## ici. Un plafond de securite est une fin LEGITIME : docs/02 §3 dit que celui
## qui mene gagne, et l'annoncer « INTERROMPUE » contredit la regle du jeu
## devant le public. Un arret — operateur, lien perdu, fermeture — n'a pas de
## vainqueur : lui seul merite le mot.
func was_stopped() -> bool:
	return interrupted and end_reason == RaceRule.EndReason.NONE


## Vrai si un autre rider classe a franchi dans la MEME trame — docs/02 §1 :
## ex aequo « photo-finish », que l'interface doit dire.
func is_dead_heat(rider: int) -> bool:
	# PAS EN MODE TEMPS. Tout le monde y « arrive » a l'instant du gong
	# (`rule_time.gd`) : l'egalite des temps est la regle, pas un photo-finish.
	# Sans cette garde, chaque course en temps marquait TOUS ses coureurs ex
	# aequo, et le tableau operateur affichait la legende a chaque fois.
	if mode == "temps":
		return false
	if finished_ms[rider] <= 0:
		return false
	for other: int in ranking:
		if other != rider and finished_ms[other] == finished_ms[rider]:
			return true
	return false


## Le nom tel qu'un ECRAN doit l'afficher : celui du depart, borne a la largeur
## affichable. Les deux moitiees ont ete corrigees a des tours differents, puis
## recopiees ensemble dans quatre ecrans ; les composer ici evite qu'un
## cinquieme n'en oublie une.
func display_name(rider: int) -> String:
	return Roster.shorten(rider_name(rider))


## Le temps COURU par un rider — la seule definition, docs/02 §5 : son
## arrivee s'il a fini, son elimination s'il a saute, sinon la fin de la
## course (gong du mode temps, plafond de poursuite, interruption). C'est
## aussi la base de sa moyenne. Jamais 0 pour un rider classe.
func raced_ms(rider: int) -> int:
	if finished_ms[rider] > 0:
		return finished_ms[rider]
	if eliminated[rider] and eliminated_ms[rider] > 0:
		return eliminated_ms[rider]
	return elapsed_ms


## Le nom du depart, ou « Piste N » — jamais une ligne vide.
## Le dossard d'une piste, tel qu'au depart. Vide si l'operateur n'en a pas
## saisi — la plupart des soirees s'en passent.
## Un dossard relu d'un fichier, ramene a du texte.
##
## LE FICHIER N'EST PAS UNE ENTREE SURE. JSON n'a qu'un type numerique : un
## dossard ecrit en nombre revient en FLOTTANT, et `str()` en fait « 7.0 » — un
## numero a virgule sur un tableau de resultats se lit comme une erreur du
## logiciel. Le roster n'en produit jamais, mais un fichier edite a la main ou
## venu d'un autre outil, si. Meme raisonnement que la couleur d'une piste, qui
## est validee a la relecture pour la meme raison.
static func _as_dossard(value: Variant) -> String:
	if value is float or value is int:
		return str(int(value))
	return str(value)


func rider_dossard(rider: int) -> String:
	return str(rider_dossards.get(rider, ""))


func rider_name(rider: int) -> String:
	var name := str(rider_names.get(rider, ""))
	return name if not name.is_empty() else "Piste %d" % (rider + 1)


func rank_of(rider: int) -> int:
	var index := ranking.find(rider)
	return index + 1 if index >= 0 else 0


func winner() -> int:
	return ranking[0] if not ranking.is_empty() else -1


func end_reason_name() -> String:
	match end_reason:
		RaceRule.EndReason.ALL_FINISHED:
			return "tous arrivés"
		RaceRule.EndReason.TIME_ELAPSED:
			return "durée écoulée"
		RaceRule.EndReason.LAST_ONE_STANDING:
			return "dernier en course"
		RaceRule.EndReason.TIME_CAP:
			return "plafond de durée"
		RaceRule.EndReason.DISTANCE_CAP:
			return "plafond de distance"
	return "indéterminé"


## Relit un JSON de course (`recorder._write_json`) tel quel, SANS rejouer :
## c'est l'historique du jour, pas le rejeu — lui recalcule tout (replay.gd).
## `data` est le document entier ; le bloc `result` est lu par rider, indexe
## par piste, comme il a ete ecrit.
static func from_json(data: Dictionary) -> RaceResult:
	var out := RaceResult.new()
	var block: Dictionary = data.get("result", {})
	out.uuid = str(data.get("uuid", ""))
	out.started_at_iso = str(data.get("started_at", ""))
	out.finished_at_iso = str(data.get("finished_at", ""))
	out.config = Replay.config_from_dict(data.get("config", {}))
	out.mode = str(data.get("config", {}).get("mode", ""))
	# JSON n'a qu'un type numerique : tout revient en float.
	for value: Variant in block.get("ranking", []):
		out.ranking.append(int(value))
	out.elapsed_ms = int(block.get("elapsed_ms", 0))
	out.end_reason = int(block.get("end_reason", 0)) as RaceRule.EndReason
	out.interrupted = bool(block.get("interrupted", false))
	out.interruption_note = str(block.get("interruption_note", ""))
	# Les cles du roster sont des chaines en JSON.
	var roster: Dictionary = data.get("roster", {})
	for lane: Variant in roster:
		var entry: Dictionary = roster[lane]
		out.rider_names[int(str(lane))] = str(entry.get("name", ""))
		# LE JSON PORTAIT DEJA LE DOSSARD : le fichier enregistre le roster
		# entier, on ne le relisait simplement pas. Les courses deja ecrites
		# retrouvent donc leurs numeros sans changement de format.
		out.rider_dossards[int(str(lane))] = _as_dossard(entry.get("dossard", ""))
	for rider: int in range(Protocol.MAX_RIDERS):
		out.finished_ms[rider] = int(_nth(block.get("finished_ms", []), rider, 0))
		out.eliminated_ms[rider] = int(_nth(block.get("eliminated_ms", []), rider, 0))
		out.distance_m[rider] = float(_nth(block.get("distance_m", []), rider, 0.0))
		out.avg_kph[rider] = float(_nth(block.get("avg_kph", []), rider, 0.0))
		out.max_kph[rider] = float(_nth(block.get("max_kph", []), rider, 0.0))
		out.eliminated[rider] = bool(_nth(block.get("eliminated", []), rider, false))
		out.false_started[rider] = bool(_nth(block.get("false_started", []), rider, false))
	return out


static func _nth(values: Variant, index: int, fallback: Variant) -> Variant:
	if values is Array and index < (values as Array).size():
		return (values as Array)[index]
	return fallback


static func from_state(state: RaceState, rule: RaceRule, reason: RaceRule.EndReason) -> RaceResult:
	var result := RaceResult.new()
	result.config = state.config.duplicate_config()
	result.mode = state.config.mode_name()
	result.elapsed_ms = state.elapsed_ms
	result.end_reason = reason
	result.ranking = rule.final_ranking(state)
	for rider: int in range(Protocol.MAX_RIDERS):
		result.finished_ms[rider] = state.finished_ms[rider]
		# JAMAIS DE DISTANCE NEGATIVE AU RESULTAT. La position d'un penalise est
		# negative tant qu'il n'a pas remonte son handicap ; si la course
		# s'arrete la — abandon, elimination en poursuite, gong d'une course en
		# temps trop courte — c'est cette valeur qui partait au PODIUM PUBLIC,
		# au tableau de l'operateur, au CSV et au JSON.
		#
		# La moyenne avait deja ete corrigee pour la meme raison, et le
		# commentaire juste en dessous raconte le `-3272 km/h` qu'elle donnait.
		# La distance, elle, etait restee brute : la moitie du defaut avait ete
		# reparee. Une distance parcourue negative n'a aucun sens, et docs/02
		# §4 pose deja le principe — le handicap est un decalage de depart, pas
		# une distance parcourue.
		#
		# Le CLASSEMENT n'en depend pas : il est calcule sur l'etat, avant, et
		# range dans `ranking`. Borner ici ne change donc l'ordre de personne.
		result.distance_m[rider] = maxf(state.distance_m[rider], 0.0)
		result.max_kph[rider] = state.max_speed_kph[rider]
		result.eliminated[rider] = state.eliminated[rider]
		result.eliminated_ms[rider] = state.eliminated_ms[rider]
		result.false_started[rider] = state.false_started[rider]
		# Vitesse moyenne sur le temps REELLEMENT couru par ce rider : un rider
		# arrive a mi-course ne doit pas voir sa moyenne diluee par le temps
		# pendant lequel il attendait les autres. Un ELIMINE non plus : sa
		# distance est figee a l'instant ou il a saute, son temps l'est donc
		# aussi. Le calculer sur toute la course donnait une moyenne trop basse.
		var ms := state.elapsed_ms
		if state.finished_ms[rider] > 0:
			ms = state.finished_ms[rider]
		elif state.eliminated_ms[rider] > 0:
			ms = state.eliminated_ms[rider]
		# LA DISTANCE REELLEMENT ROULEE, pas la position. Un rider penalise part
		# en arriere : sa position est negative tant qu'il n'a pas remonte son
		# handicap, et sa moyenne valait alors -3272 km/h — un chiffre qui
		# partait au podium public et au CSV. Le handicap est un decalage de
		# depart, pas une distance parcourue.
		var rolled := state.distance_m[rider] - state.handicap_m[rider]
		if ms > 0:
			result.avg_kph[rider] = maxf(rolled, 0.0) / (float(ms) / 1000.0) * 3.6
	return result
