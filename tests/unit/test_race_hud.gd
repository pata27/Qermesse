## L'habillage public reagit aux alertes — docs/02 §4, docs/01 §6.2, docs/04.
extends GutTest

var _controller: AppController
var _hud: RaceHud


func before_each() -> void:
	_controller = AppController.new()
	_controller.preferences_enabled = false
	_controller.recorder_logs_dir = ProjectSettings.globalize_path("user://test_hud/logs")
	_controller.recorder_races_dir = ProjectSettings.globalize_path("user://test_hud/races")
	add_child_autofree(_controller)
	_hud = RaceHud.new()
	add_child_autofree(_hud)
	_hud.setup(_controller)


func test_le_faux_depart_s_affiche_en_alerte_sur_l_ecran_public() -> void:
	# docs/02 §4, AVERTISSEMENT : « bandeau + son, la course continue ».
	_controller.race_state_changed.emit(RaceEngine.State.IDLE, RaceEngine.State.ARMING)
	_controller.false_start_detected.emit(2, RaceConfig.FalseStartPolicy.WARN)
	assert_string_contains(_hud.notice_text(), "FAUX DEPART")
	assert_string_contains(_hud.notice_text(), "PISTE 3")
	assert_eq(_hud.notice_color(), RaceHud.ALERT)


func test_le_lien_perdu_s_affiche_puis_s_efface_au_retour() -> void:
	# docs/01 §6.2 : « gel du rendu sur la derniere valeur connue, bandeau
	# d'alerte » ; le lien revient sous 3 s, la course reprend — le bandeau
	# n'a plus rien a dire.
	_controller.race_state_changed.emit(RaceEngine.State.IDLE, RaceEngine.State.ARMING)
	_controller.race_state_changed.emit(RaceEngine.State.COUNTDOWN, RaceEngine.State.RUNNING)
	_controller.link_state_changed.emit(Protocol.State.LINK_LOST)
	assert_string_contains(_hud.notice_text(), "LIEN PERDU")
	assert_eq(_hud.notice_color(), RaceHud.ALERT)
	_controller.link_state_changed.emit(Protocol.State.IDENTIFIED)
	assert_eq(_hud.notice_text(), "", "plus d'alerte une fois le lien revenu")


func test_le_lien_perdu_n_efface_pas_une_elimination_au_retour() -> void:
	_controller.race_state_changed.emit(RaceEngine.State.IDLE, RaceEngine.State.ARMING)
	_controller.race_state_changed.emit(RaceEngine.State.COUNTDOWN, RaceEngine.State.RUNNING)
	_controller.link_state_changed.emit(Protocol.State.LINK_LOST)
	_controller.link_state_changed.emit(Protocol.State.IDENTIFIED)
	_controller.rider_eliminated.emit(1, 4, 50.0)
	_controller.link_state_changed.emit(Protocol.State.LINK_LOST)
	_controller.link_state_changed.emit(Protocol.State.IDENTIFIED)
	# Le retour du lien ne rend que ce qu'il avait recouvert.
	assert_string_contains(_hud.notice_text(), "ELIMINEE")


func test_la_course_interrompue_le_dit_au_public() -> void:
	_controller.race_state_changed.emit(RaceEngine.State.IDLE, RaceEngine.State.ARMING)
	_controller.race_state_changed.emit(RaceEngine.State.COUNTDOWN, RaceEngine.State.RUNNING)
	_controller.race_aborted.emit("lien perdu au-dela du delai de grace")
	_controller.race_state_changed.emit(RaceEngine.State.RUNNING, RaceEngine.State.IDLE)
	assert_string_contains(_hud.notice_text(), "COURSE INTERROMPUE")
	assert_eq(_hud.notice_color(), RaceHud.ALERT)
