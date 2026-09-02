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


func _init() -> void:
	finished_ms.resize(Protocol.MAX_RIDERS)
	eliminated_ms.resize(Protocol.MAX_RIDERS)
	distance_m.resize(Protocol.MAX_RIDERS)
	avg_kph.resize(Protocol.MAX_RIDERS)
	max_kph.resize(Protocol.MAX_RIDERS)
	for i: int in range(Protocol.MAX_RIDERS):
		eliminated.append(false)
		false_started.append(false)


func rank_of(rider: int) -> int:
	var index := ranking.find(rider)
	return index + 1 if index >= 0 else 0


func winner() -> int:
	return ranking[0] if not ranking.is_empty() else -1


func end_reason_name() -> String:
	match end_reason:
		RaceRule.EndReason.ALL_FINISHED:
			return "tous arrives"
		RaceRule.EndReason.TIME_ELAPSED:
			return "duree ecoulee"
		RaceRule.EndReason.LAST_ONE_STANDING:
			return "dernier en course"
		RaceRule.EndReason.TIME_CAP:
			return "plafond de duree"
		RaceRule.EndReason.DISTANCE_CAP:
			return "plafond de distance"
	return "indetermine"


static func from_state(state: RaceState, rule: RaceRule, reason: RaceRule.EndReason) -> RaceResult:
	var result := RaceResult.new()
	result.config = state.config.duplicate_config()
	result.mode = state.config.mode_name()
	result.elapsed_ms = state.elapsed_ms
	result.end_reason = reason
	result.ranking = rule.final_ranking(state)
	for rider: int in range(Protocol.MAX_RIDERS):
		result.finished_ms[rider] = state.finished_ms[rider]
		result.distance_m[rider] = state.distance_m[rider]
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
		if ms > 0:
			result.avg_kph[rider] = state.distance_m[rider] / (float(ms) / 1000.0) * 3.6
	return result
