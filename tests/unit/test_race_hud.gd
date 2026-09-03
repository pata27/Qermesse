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
	assert_string_contains(_hud.notice_text(), "FAUX DÉPART")
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
	assert_string_contains(_hud.notice_text(), "ÉLIMINÉE")


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
	capped.interruption_note = "plafond de sécurité atteint : plafond de durée"
	capped.rider_names = {0: "Alice", 1: "Bob"}

	var shown := _podium_apres(capped)
	assert_false(shown.contains("INTERROMPUE"), "elle s'est decidee, elle n'a pas ete arretee")
	assert_string_contains(shown, "ARRIVÉE")
	assert_string_contains(shown, "plafond", "et le motif reste affiche")


func test_le_bandeau_vainqueur_ne_barre_pas_une_victoire_au_plafond() -> void:
	# « VAINQUEUR — P1 Alice [INTERROMPUE] » : le bandeau se contredisait
	# lui-meme. Au plafond, docs/02 §3 dit que celui qui mene gagne.
	var config := RaceConfig.new()
	config.mode = RaceConfig.Mode.PURSUIT
	config.active_riders = [0, 1]
	var capped := RaceResult.new()
	capped.mode = "poursuite"
	capped.config = config
	capped.ranking = [0, 1]
	capped.interrupted = true
	capped.end_reason = RaceRule.EndReason.TIME_CAP
	capped.rider_names = {0: "Alice", 1: "Bob"}
	_controller.race_finished.emit(capped)
	assert_string_contains(_hud.notice_text(), "VAINQUEUR")
	assert_false(_hud.notice_text().contains("INTERROMPUE"), "il a bien gagne")

	capped.end_reason = RaceRule.EndReason.NONE
	_controller.race_finished.emit(capped)
	assert_string_contains(_hud.notice_text(), "INTERROMPUE", "la, la course a ete arretee")


func test_une_course_arretee_est_bien_annoncee_interrompue() -> void:
	var stopped := RaceResult.new()
	stopped.mode = "distance"
	stopped.ranking = [0, 1]
	stopped.interrupted = true
	stopped.end_reason = RaceRule.EndReason.NONE
	stopped.interruption_note = "arrêt opérateur"
	stopped.rider_names = {0: "Alice", 1: "Bob"}

	var shown := _podium_apres(stopped)
	assert_string_contains(shown, "INTERROMPUE", "la, personne n'a gagne")
	assert_string_contains(shown, "arrêt opérateur")


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
	assert_string_contains(_hud.decision_text(), "décision dans")
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


func test_en_ecran_scinde_chaque_carte_va_dans_le_volet_de_son_coureur() -> void:
	# QUATRE VOLETS, QUATRE CARTES EN HAUT A GAUCHE. Le spectateur qui regarde
	# le quatrieme volet lisait la vitesse de son coureur a l'autre bout de
	# l'ecran, empilee sous celles des trois autres. Chaque carte se pose
	# desormais dans le volet qui montre son coureur (docs/04 §5).
	for lane: int in range(Protocol.MAX_RIDERS):
		_controller.roster.set_active(lane, true)
	_hud.rebuild_cards()
	_hud.set_compact(true)
	# Quatre volets sur un ecran de 1920 : 480 px chacun.
	_hud.set_pane_layout(
		{0: 0, 1: 1, 2: 2, 3: 3}, PackedFloat32Array([0.0, 480.0, 960.0, 1440.0, 1920.0])
	)
	for lane: int in range(Protocol.MAX_RIDERS):
		assert_almost_eq(
			_hud.card_position(lane).x,
			480.0 * lane + (RaceHud.CARD_MARGIN_X if lane == 0 else RaceHud.CARD_MARGIN_X * 0.4),
			1.0,
			"la carte de la piste %d commence dans son volet" % (lane + 1)
		)
	assert_almost_eq(
		_hud.card_position(3).y, _hud.card_position(0).y, 0.5,
		"un seul coureur par volet : toutes les cartes sur la meme ligne"
	)
	# Et elle y TIENT : une carte qui deborderait sur le volet voisin dirait la
	# vitesse du mauvais coureur.
	for lane: int in range(Protocol.MAX_RIDERS):
		var card_width := RaceHud.CARD_WIDTH * _hud.card_scale(lane)
		assert_lt(
			_hud.card_position(lane).x + card_width, 480.0 * (lane + 1),
			"la carte de la piste %d tient dans son volet" % (lane + 1)
		)


func test_deux_coureurs_dans_un_meme_volet_empilent_leurs_cartes() -> void:
	for lane: int in range(Protocol.MAX_RIDERS):
		_controller.roster.set_active(lane, true)
	_hud.rebuild_cards()
	_hud.set_compact(true)
	# Deux paquets de deux : le decoupage que produit le profil `deux-groupes`.
	_hud.set_pane_layout({0: 0, 1: 0, 2: 1, 3: 1}, PackedFloat32Array([0.0, 960.0, 1920.0]))
	assert_almost_eq(_hud.card_position(0).x, RaceHud.CARD_MARGIN_X, 1.0, "piste 1 a gauche")
	assert_almost_eq(_hud.card_position(1).x, RaceHud.CARD_MARGIN_X, 1.0, "piste 2 aussi")
	assert_gt(_hud.card_position(1).y, _hud.card_position(0).y, "et sous elle")
	assert_almost_eq(
		_hud.card_position(2).x, 960.0 + RaceHud.CARD_MARGIN_X * 0.4, 1.0,
		"piste 3 dans le second volet"
	)
	assert_almost_eq(
		_hud.card_position(2).y, _hud.card_position(0).y, 0.5,
		"en haut de son volet, pas a la troisieme ligne"
	)


func test_sans_ecran_scinde_les_cartes_restent_en_colonne() -> void:
	for lane: int in range(Protocol.MAX_RIDERS):
		_controller.roster.set_active(lane, true)
	_hud.rebuild_cards()
	for lane: int in range(Protocol.MAX_RIDERS):
		assert_almost_eq(
			_hud.card_position(lane).x, RaceHud.CARD_MARGIN_X, 1.0,
			"plein cadre : la colonne de gauche, comme avant"
		)
	assert_gt(_hud.card_position(3).y, _hud.card_position(0).y, "empilees")


func test_les_cartes_sont_lisibles_des_le_decompte() -> void:
	# CE QUE LE PUBLIC VOIT PENDANT LE DECOMPTE. Les cartes n'etaient remplies
	# qu'a la premiere trame `R:` : pendant les trois secondes du decompte, elles
	# affichaient un nom et deux lignes VIDES. Sur un mur, un cadre vide se lit
	# comme un affichage casse, au moment precis ou tout le monde regarde.
	_controller.roster.rider(0).name = "Lucie"
	_controller.roster.set_active(0, true)
	_controller.settings.distance_m = 250.0
	_hud.rebuild_cards()

	assert_string_contains(_hud.card_speed_text(0), "0.0 km/h", "la vitesse part de zero")
	assert_string_contains(_hud.card_detail_text(0), "0 m parcourus", "la distance aussi")
	assert_string_contains(_hud.card_detail_text(0), "250 m", "et l'objectif est annonce")


func test_les_cartes_annoncent_la_duree_en_mode_temps() -> void:
	_controller.roster.set_active(0, true)
	_controller.settings.mode = RaceConfig.Mode.TIME
	_controller.settings.duration_s = 60.0
	_hud.rebuild_cards()
	assert_string_contains(_hud.card_detail_text(0), "60.0 s", "le temps a courir")


func test_le_podium_public_explique_la_marque_des_elimines() -> void:
	# CE QUE LE PUBLIC LIT. Un elimine porte « 14.16 s ✕ » — et rien, nulle
	# part, ne dit ce que cette croix signifie. Le tableau de l'operateur, lui,
	# l'explique depuis toujours : « x = elimine a cet instant ». L'ecran public
	# est vu par cent personnes, celui de l'operateur par une.
	var result := RaceResult.new()
	result.mode = "poursuite"
	result.ranking = [0, 1] as Array[int]
	result.finished_ms = [15540, 0, 0, 0] as Array[int]
	result.eliminated_ms = [0, 14160, 0, 0] as Array[int]
	result.eliminated = [false, true, false, false] as Array[bool]
	result.end_reason = RaceRule.EndReason.LAST_ONE_STANDING
	var text := _podium_apres(result)
	assert_string_contains(text, "✕", "la marque est bien la")
	assert_string_contains(text, "✕ = éliminé", "et elle est expliquee")


func test_le_podium_n_explique_pas_une_marque_absente() -> void:
	# Une legende permanente serait du bruit : sur une arrivee ordinaire, il n'y
	# a aucune croix a expliquer.
	var result := RaceResult.new()
	result.mode = "distance"
	result.ranking = [0, 1] as Array[int]
	result.finished_ms = [15540, 16000, 0, 0] as Array[int]
	result.end_reason = RaceRule.EndReason.ALL_FINISHED
	var text := _podium_apres(result)
	assert_false(text.contains("✕"), "aucune croix")
	assert_false(text.contains("= éliminé"), "donc aucune legende")


func test_le_chiffre_d_ecart_ne_bat_pas_a_ecart_stable() -> void:
	# Le gros chiffre de la poursuite est lisse PUIS filtre : il ne se reecrit
	# que si la valeur lissee s'ecarte d'au moins `GAP_STEP_M` du DERNIER
	# CHIFFRE IMPRIME — et non de la derniere variation, nuance qui m'a d'abord
	# fait ecrire un test faux. Sans ce filtre, le dernier chiffre battait a
	# chaque image. Rien ne l'eprouvait.
	var tension := RaceTension.new()
	tension.build(1328.0)
	add_child_autofree(tension)
	tension.visible = true

	tension.set_gap(10.0, 50.0)
	for step: int in range(240):
		tension.advance(1.0 / 60.0)
	var settled := tension.gap_text()
	assert_string_contains(settled, "m", "le chiffre est ecrit avec son unite")

	# A cible constante, plus une seule reecriture : c'est la propriete qui
	# empeche le scintillement.
	for step: int in range(240):
		tension.advance(1.0 / 60.0)
		assert_eq(tension.gap_text(), settled, "immobile a ecart stable")

	# Un ecart qui change vraiment, lui, se voit.
	tension.set_gap(20.0, 50.0)
	for step: int in range(240):
		tension.advance(1.0 / 60.0)
	assert_ne(tension.gap_text(), settled, "un ecart qui change vraiment se voit")


func test_le_bandeau_d_abandon_tient_dans_l_ecran_et_s_y_centre() -> void:
	# Vu a l'image, pas au test : « COURSE INTERROMPUE — arrêt opérateur »
	# mesure 895 px pour une boite de 840 et sortait par la droite. Le pire cas
	# est bien plus long encore, et rien ne l'aurait signale — les assertions
	# lisent du texte, pas des largeurs.
	#
	# L'abandon prend maintenant tout l'ecran, au milieu : la course est finie,
	# et ce sont les coureurs qu'il faut atteindre, sur leurs rouleaux.
	_controller.race_state_changed.emit(RaceEngine.State.IDLE, RaceEngine.State.ARMING)
	_controller.race_state_changed.emit(RaceEngine.State.COUNTDOWN, RaceEngine.State.RUNNING)
	for note: String in [
		"arrêt opérateur",
		"lien perdu au-delà du délai de grâce",
		"fermeture du logiciel",
		"",
	]:
		_controller.race_aborted.emit(note)
		var metrics := _hud.notice_metrics()
		var rect: Rect2 = metrics["rect"]
		var width: float = metrics["text_width"]
		assert_lt(width, rect.size.x, "« %s » tient dans sa boite" % note)
		assert_gt(rect.position.x, 0.0, "la boite commence dans l'ecran")
		assert_lt(rect.position.x + rect.size.x, 1920.0, "et finit dedans")
		assert_almost_eq(
			rect.position.x + rect.size.x * 0.5, 960.0, 1.0, "centree sur l'ecran"
		)

	# Rien ne doit rester SOUS les cartes des coureurs : a quatre pistes elles
	# descendent jusqu'au milieu de l'ecran, et le bandeau y passait dessous.
	# Il monte donc sur la couche superieure, la scene s'assombrit, et les
	# cartes s'effacent — ce qu'elles montrent n'a plus cours.
	var big := _hud.notice_metrics()
	assert_true(big["above_cards"], "le bandeau d'abandon passe au-dessus des cartes")
	assert_true(big["veil"], "et la scene s'assombrit derriere lui")

	# La course suivante remet tout en place.
	_controller.race_state_changed.emit(RaceEngine.State.IDLE, RaceEngine.State.ARMING)
	var back := _hud.notice_metrics()
	assert_false(back["veil"], "le voile s'en va au reamement")
	assert_false(back["above_cards"], "et le bandeau redescend a sa place")

	# Les autres bandeaux, eux, restent a leur place sous la bande : la course
	# continue et ils ne doivent pas masquer ce qu'elle montre.
	_controller.link_state_changed.emit(Protocol.State.LINK_LOST)
	var small: Rect2 = _hud.notice_metrics()["rect"]
	assert_lt(small.size.x, RaceHud.NOTICE_BIG_WIDTH, "le lien perdu ne prend pas tout l'ecran")
	assert_lt(small.position.y, 300.0, "il reste sous la bande")
