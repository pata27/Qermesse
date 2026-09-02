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


func test_aucun_nom_ne_deborde_de_sa_carte() -> void:
	# Compter les caracteres ne suffit pas : dix-huit lettres larges font
	# 623 px la ou la carte en offre 414. La carte coupe donc a la largeur
	# REELLE. Ce test cessera d'etre vrai si l'on deplace le compteur de
	# vitesse ou si l'on grossit le nom.
	_controller.roster.rider(0).name = "M".repeat(Roster.MAX_DISPLAY_NAME)
	_controller.roster.set_active(0, true)
	_hud.rebuild_cards()
	var label := _hud.card_name_label(0)
	assert_not_null(label, "la carte de la piste 1 existe")
	var budget := RaceHud.CARD_SPEED_X - RaceHud.CARD_NAME_X
	assert_almost_eq(label.size.x, budget, 0.5, "le nom est borne a la place disponible")
	assert_eq(
		label.text_overrun_behavior, TextServer.OVERRUN_TRIM_ELLIPSIS,
		"et ce qui depasse est coupe avec des points de suspension"
	)

	# La borne en caracteres reste utile : un nom REALISTE doit tenir en
	# entier, sinon elle est trop large et coupe tout le monde.
	var realistic := Label.new()
	realistic.add_theme_font_size_override("font_size", RaceHud.CARD_NAME_FONT)
	add_child_autofree(realistic)
	realistic.text = "P4  Jean-Baptiste"
	assert_lt(realistic.get_minimum_size().x, budget, "un nom courant tient sans etre coupe")


func test_l_ecran_public_nomme_les_coureurs_du_depart() -> void:
	# Meme regle que le tableau operateur, corrigee la-bas et oubliee ici :
	# renommer les pistes entre deux courses ne reecrit pas l'histoire. Le
	# bandeau et le podium lisaient le roster COURANT — l'operateur voyait
	# Alice sur son tableau pendant que le public lisait Carole.
	_controller.roster.rider(0).name = "Carole"
	_controller.roster.rider(1).name = "Dan"
	var result := RaceResult.new()
	result.mode = "distance"
	result.ranking = [1, 0]
	result.end_reason = RaceRule.EndReason.ALL_FINISHED
	result.finished_ms[1] = 7900
	result.finished_ms[0] = 8000
	result.rider_names = {0: "Alice", 1: "Bob"}
	_controller.race_finished.emit(result)

	assert_string_contains(_hud.notice_text(), "Bob", "le bandeau nomme le vainqueur du depart")
	assert_false(_hud.notice_text().contains("Dan"), "pas le roster courant")

	# Le podium attend que la celebration se joue.
	_hud._process(RaceHud.PODIUM_DELAY_S + 0.1)
	var podium := _hud.podium_text()
	assert_string_contains(podium, "Alice")
	assert_string_contains(podium, "Bob")
	assert_false(podium.contains("Carole"), "le roster courant ne reecrit pas l'histoire")
	assert_false(podium.contains("Dan"))


func test_la_politique_ignorer_ne_dit_rien_au_public() -> void:
	# docs/02 §4 : IGNORE est « loggue UNIQUEMENT (comportement v1) ». Le CSV
	# porte la ligne FALSE_START ; l'ecran public, lui, ne montre rien. Un
	# bandeau rouge malgre la politique choisie, c'est la politique ignoree.
	_controller.race_state_changed.emit(RaceEngine.State.IDLE, RaceEngine.State.ARMING)
	_controller.false_start_detected.emit(1, RaceConfig.FalseStartPolicy.IGNORE)
	assert_eq(_hud.notice_text(), "", "rien sur l'ecran public")


func test_la_penalite_dit_au_public_pourquoi_un_rider_part_en_arriere() -> void:
	# docs/02 §4, PENALITE : « le rider fautif demarre avec un handicap de P
	# metres ». Sans un mot, le public voit un coureur inexplicablement
	# distance des le depart.
	_controller.settings.false_start_penalty_m = 10.0
	_controller.race_state_changed.emit(RaceEngine.State.IDLE, RaceEngine.State.ARMING)
	_controller.false_start_detected.emit(1, RaceConfig.FalseStartPolicy.PENALTY)
	assert_string_contains(_hud.notice_text(), "PISTE 2")
	assert_string_contains(_hud.notice_text(), "10 m")
	assert_eq(_hud.notice_color(), RaceHud.ALERT)


func test_une_course_interrompue_dit_pourquoi() -> void:
	# docs/02 §4, RELANCE : « message faux depart rider N ». Le motif de
	# l'abandon etait connu du moteur et jete a l'affichage.
	_controller.race_state_changed.emit(RaceEngine.State.IDLE, RaceEngine.State.ARMING)
	_controller.race_state_changed.emit(RaceEngine.State.COUNTDOWN, RaceEngine.State.RUNNING)
	_controller.race_aborted.emit("faux depart piste 1")
	assert_string_contains(_hud.notice_text(), "INTERROMPUE")
	assert_string_contains(_hud.notice_text(), "faux depart piste 1")


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


func _podium_apres(result: RaceResult) -> String:
	_controller.race_state_changed.emit(RaceEngine.State.IDLE, RaceEngine.State.ARMING)
	_controller.race_state_changed.emit(RaceEngine.State.COUNTDOWN, RaceEngine.State.RUNNING)
	_controller.race_finished.emit(result)
	_hud._process(RaceHud.PODIUM_DELAY_S + 0.1)
	return _hud.podium_text()


func test_une_poursuite_decidee_au_plafond_n_est_pas_annoncee_interrompue() -> void:
	# docs/02 §3 : au plafond de securite, « celui qui mene gagne ». C'est une
	# fin legitime, avec un vainqueur. Le podium l'annoncait pourtant
	# INTERROMPUE en gros — la meme incoherence que j'avais corrigee dans la
	# liste des courses du jour, jamais reportee ici.
	var config := RaceConfig.new()
	config.mode = RaceConfig.Mode.PURSUIT
	config.active_riders = [0, 1]
	var capped := RaceResult.new()
	capped.mode = "poursuite"
	capped.config = config
	capped.ranking = [0, 1]
	capped.interrupted = true
	capped.end_reason = RaceRule.EndReason.TIME_CAP
	capped.interruption_note = "plafond de securite atteint : plafond de duree"
	capped.rider_names = {0: "Alice", 1: "Bob"}

	var shown := _podium_apres(capped)
	assert_false(shown.contains("INTERROMPUE"), "elle s'est decidee, elle n'a pas ete arretee")
	assert_string_contains(shown, "ARRIVÉE")
	assert_string_contains(shown, "plafond", "et le motif reste affiche")


func test_une_course_arretee_est_bien_annoncee_interrompue() -> void:
	var stopped := RaceResult.new()
	stopped.mode = "distance"
	stopped.ranking = [0, 1]
	stopped.interrupted = true
	stopped.end_reason = RaceRule.EndReason.NONE
	stopped.interruption_note = "arret operateur"
	stopped.rider_names = {0: "Alice", 1: "Bob"}

	var shown := _podium_apres(stopped)
	assert_string_contains(shown, "INTERROMPUE", "la, personne n'a gagne")
	assert_string_contains(shown, "arret operateur")


func test_l_ecart_ne_s_affiche_pas_avant_le_depart() -> void:
	# Vu sur une capture : pendant le decompte, l'ecran de poursuite montrait
	# « 0.0 m » et une barre de tension vide, en concurrence avec le chiffre du
	# decompte. Tout le monde est sur la ligne : l'ecart ne dit rien encore.
	# En mode temps, le meme moment montre les noms des coureurs — utile.
	_controller.settings.mode = RaceConfig.Mode.PURSUIT
	_controller.race_state_changed.emit(RaceEngine.State.IDLE, RaceEngine.State.ARMING)
	assert_false(_hud.gap_visible(), "rien a montrer avant le depart")

	_controller.race_state_changed.emit(RaceEngine.State.COUNTDOWN, RaceEngine.State.RUNNING)
	assert_true(_hud.gap_visible(), "des que ca roule, c'est le sujet du mode")

	_controller.race_state_changed.emit(RaceEngine.State.RUNNING, RaceEngine.State.FINISHED)
	assert_true(_hud.gap_visible(), "et l'ecart final reste lisible")


func test_la_jauge_de_decision_se_tait_une_fois_la_poursuite_decidee() -> void:
	_controller.settings.mode = RaceConfig.Mode.PURSUIT
	_controller.race_state_changed.emit(RaceEngine.State.IDLE, RaceEngine.State.ARMING)
	_controller.race_state_changed.emit(RaceEngine.State.COUNTDOWN, RaceEngine.State.RUNNING)
	var config := _controller.current_config()
	config.active_riders = [0, 1]
	var state := RaceState.new(config)
	state.elapsed_ms = 10000
	_controller.progress_updated.emit(state)
	assert_string_contains(_hud.decision_text(), "decision dans")
	_controller.race_state_changed.emit(RaceEngine.State.RUNNING, RaceEngine.State.FINISHED)
	assert_eq(_hud.decision_text(), "", "la decision est prise")


func test_la_deuxieme_course_ne_part_pas_avec_la_vitesse_de_la_premiere() -> void:
	# Les lissages survivaient aux cartes : a la deuxieme course, la premiere
	# trame R: faisait DECROITRE l'ancienne vitesse sur des coureurs qui
	# demarrent.
	var config := _controller.current_config()
	config.active_riders = [0, 1]
	var state := RaceState.new(config)
	_controller.race_state_changed.emit(RaceEngine.State.IDLE, RaceEngine.State.ARMING)
	_controller.race_state_changed.emit(RaceEngine.State.COUNTDOWN, RaceEngine.State.RUNNING)
	state.display_speed_kph[0] = 52.0
	_controller.progress_updated.emit(state)
	for i: int in range(60):
		_hud._process(1.0 / 30.0)
	assert_string_contains(_hud.card_speed_text(0), "52.0")

	# Nouvelle course : les cartes sont neuves, la premiere trame dit 0.
	_controller.race_state_changed.emit(RaceEngine.State.RUNNING, RaceEngine.State.FINISHED)
	_controller.race_state_changed.emit(RaceEngine.State.IDLE, RaceEngine.State.ARMING)
	_controller.race_state_changed.emit(RaceEngine.State.COUNTDOWN, RaceEngine.State.RUNNING)
	var fresh := RaceState.new(config)
	_controller.progress_updated.emit(fresh)
	_hud._process(1.0 / 30.0)
	assert_string_contains(_hud.card_speed_text(0), "0.0 km/h")
	assert_false(_hud.card_speed_text(0).contains("5"), "pas une vitesse heritee qui decroit")


func test_la_course_interrompue_le_dit_au_public() -> void:
	_controller.race_state_changed.emit(RaceEngine.State.IDLE, RaceEngine.State.ARMING)
	_controller.race_state_changed.emit(RaceEngine.State.COUNTDOWN, RaceEngine.State.RUNNING)
	_controller.race_aborted.emit("lien perdu au-dela du delai de grace")
	_controller.race_state_changed.emit(RaceEngine.State.RUNNING, RaceEngine.State.IDLE)
	assert_string_contains(_hud.notice_text(), "COURSE INTERROMPUE")
	assert_eq(_hud.notice_color(), RaceHud.ALERT)
