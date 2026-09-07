## Tests de la synthèse audio — jalon J5.
##
## Tout se teste SANS carte son : `SoundForge` ne produit que des données. Les
## essais tournent d'ailleurs avec `--audio-driver Dummy`, pour qu'aucun son ne
## sorte pendant le développement.
extends GutTest


func _peak(stream: AudioStreamWAV) -> float:
	var peak := 0.0
	for i: int in range(stream.data.size() / 2):
		peak = maxf(peak, absf(float(stream.data.decode_s16(i * 2)) / 32768.0))
	return peak


func _frames(stream: AudioStreamWAV) -> int:
	return stream.data.size() / 2


func test_chaque_son_est_du_16_bits_mono_a_44100() -> void:
	for stream: AudioStreamWAV in [
		SoundForge.beep(), SoundForge.horn(), SoundForge.bell(),
		SoundForge.crowd(), SoundForge.drone(), SoundForge.wind(),
	]:
		assert_eq(stream.format, AudioStreamWAV.FORMAT_16_BITS, "16 bits")
		assert_eq(stream.mix_rate, SoundForge.MIX_RATE, "44,1 kHz")
		assert_false(stream.stereo, "mono : rien ici n'est spatialisé")
		assert_gt(_frames(stream), 1000, "le son n'est pas vide")


func test_aucun_son_n_est_ecrete() -> void:
	# Un son écrêté craque, et un craquement en salle s'entend plus que le son
	# lui-même. La normalisation est faite une fois pour toutes dans `_wav`.
	for stream: AudioStreamWAV in [
		SoundForge.beep(), SoundForge.horn(), SoundForge.bell(),
		SoundForge.crowd(), SoundForge.drone(), SoundForge.wind(),
	]:
		var peak := _peak(stream)
		assert_lt(peak, 0.999, "pas de saturation")
		assert_gt(peak, 0.5, "et un niveau utile malgré tout")


func test_les_sons_en_boucle_sont_marques_comme_tels() -> void:
	for stream: AudioStreamWAV in [SoundForge.drone(), SoundForge.wind()]:
		assert_eq(stream.loop_mode, AudioStreamWAV.LOOP_FORWARD, "boucle")
		assert_eq(stream.loop_begin, 0, "depuis le début")
		assert_eq(stream.loop_end, _frames(stream), "jusqu'à la fin")
	for stream: AudioStreamWAV in [SoundForge.beep(), SoundForge.horn()]:
		assert_eq(stream.loop_mode, AudioStreamWAV.LOOP_DISABLED, "coup unique")


func test_la_boucle_de_nappe_se_raccorde_sans_clic() -> void:
	# LE défaut classique d'une boucle synthétisée : un saut d'amplitude au
	# raccord, qui s'entend comme un clic à chaque tour. La durée de la nappe
	# contient un nombre entier de périodes de chacun de ses partiels.
	var stream := SoundForge.drone()
	var frames := _frames(stream)
	var first := float(stream.data.decode_s16(0)) / 32768.0
	var last := float(stream.data.decode_s16((frames - 1) * 2)) / 32768.0
	assert_almost_eq(last, first, 0.05, "le raccord ne saute pas")


func test_la_boucle_de_vent_se_raccorde_sans_clic() -> void:
	# Le bruit n'a pas de période : c'est un fondu croisé qui fait le raccord.
	var stream := SoundForge.wind()
	var frames := _frames(stream)
	var first := float(stream.data.decode_s16(0)) / 32768.0
	var last := float(stream.data.decode_s16((frames - 1) * 2)) / 32768.0
	assert_almost_eq(last, first, 0.12, "le raccord ne saute pas")


func test_la_synthese_est_deterministe() -> void:
	# Deux appels doivent rendre exactement le même son : sans cela, un rejeu
	# ne sonnerait pas comme la course qu'il rejoue.
	assert_eq(SoundForge.crowd().data, SoundForge.crowd().data, "clameur")
	assert_eq(SoundForge.wind().data, SoundForge.wind().data, "vent")


func test_le_son_est_coupe_par_defaut() -> void:
	# docs/04 §6 : en événementiel la sono est gérée séparément. Un logiciel qui
	# sonne par-dessus la musique de la salle dès la première course est un
	# problème, pas une fonctionnalité.
	assert_true(Settings.new().audio_muted, "muet au premier lancement")


func test_le_faux_depart_a_son_buzzer() -> void:
	# docs/02 §4, AVERTISSEMENT : « bandeau + son ». Le son reste sur le bus
	# coupe par defaut : ici on verifie l'intention, pas le haut-parleur.
	var controller := AppController.new()
	controller.preferences_enabled = false
	add_child_autofree(controller)
	var audio := RaceAudio.new()
	add_child_autofree(audio)
	audio.setup(controller)
	assert_true(audio.is_muted(), "le son reste coupe : on travaille en open space")
	controller.false_start_detected.emit(0, RaceConfig.FalseStartPolicy.WARN)
	assert_eq(audio.last_cue, "faux-depart")


func test_le_volume_est_persiste_et_reapplique_au_lancement() -> void:
	# Le manuel fait regler le son LA VEILLE. Le volume ne vivait que sur le
	# bus audio : rien ne l'ecrivait dans les reglages, et le lancement suivant
	# repartait a zero — l'operateur retrouvait la sono a fond.
	var controller := AppController.new()
	controller.preferences_enabled = false
	add_child_autofree(controller)
	var audio := RaceAudio.new()
	add_child_autofree(audio)
	audio.setup(controller)

	audio.set_volume_db(-12.0)
	assert_almost_eq(controller.settings.audio_volume_db, -12.0, 0.001, "le reglage suit le curseur")

	# Le bus est global : on le repose ailleurs, sinon le lancement suivant
	# retrouverait -12 dB sans avoir rien relu.
	audio.set_volume_db(0.0)

	var later := AppController.new()
	later.preferences_enabled = false
	add_child_autofree(later)
	later.settings.audio_volume_db = -12.0
	var fresh := RaceAudio.new()
	add_child_autofree(fresh)
	fresh.setup(later)
	assert_almost_eq(fresh.volume_db(), -12.0, 0.001, "et il est reapplique au lancement")


func test_la_politique_ignorer_ne_sonne_pas() -> void:
	# docs/02 §4 : IGNORE est loggue UNIQUEMENT. « Bandeau + son » est le
	# comportement d'AVERTISSEMENT, pas celui d'IGNORE.
	var controller := AppController.new()
	controller.preferences_enabled = false
	add_child_autofree(controller)
	var audio := RaceAudio.new()
	add_child_autofree(audio)
	audio.setup(controller)
	controller.false_start_detected.emit(0, RaceConfig.FalseStartPolicy.IGNORE)
	assert_eq(audio.last_cue, "", "rien n'a ete declenche")


## Monte un controleur et sa bande-son, isoles des reglages de l'utilisateur.
func _rig() -> Array:
	var controller := AppController.new()
	controller.preferences_enabled = false
	add_child_autofree(controller)
	var audio := RaceAudio.new()
	add_child_autofree(audio)
	audio.setup(controller)
	return [controller, audio]


func test_le_decompte_et_le_depart_sonnent() -> void:
	# docs/04 §6 : « bips de decompte, klaxon de depart ». Rien ne le verifiait :
	# `last_cue` n'etait ecrit que par le faux depart, si bien que six des sept
	# sons n'etaient constates par aucun test — dans un projet ou il est interdit
	# d'en juger a l'oreille.
	var rig := _rig()
	var controller: AppController = rig[0]
	var audio: RaceAudio = rig[1]
	controller.race_state_changed.emit(RaceEngine.State.IDLE, RaceEngine.State.ARMING)
	for value: int in [3, 2, 1, 0]:
		controller.countdown_tick.emit(value)
	assert_eq(int(audio.cue_counts.get("bip", 0)), 3, "un bip par seconde du decompte")
	assert_eq(int(audio.cue_counts.get("klaxon", 0)), 1, "et le klaxon sur CD:0")
	assert_eq(audio.last_cue, "klaxon", "le depart est le dernier son entendu")


func test_la_cloche_sonne_aux_derniers_metres_et_une_seule_fois() -> void:
	var rig := _rig()
	var controller: AppController = rig[0]
	var audio: RaceAudio = rig[1]
	var config := RaceConfig.new()
	config.mode = RaceConfig.Mode.DISTANCE
	config.distance_m = 250.0
	controller.race_state_changed.emit(RaceEngine.State.IDLE, RaceEngine.State.ARMING)
	controller.race_state_changed.emit(RaceEngine.State.COUNTDOWN, RaceEngine.State.RUNNING)

	var state := RaceState.new(config)
	var physics := Physics.new(config.roller_mm)
	for metres: float in [100.0, 180.0, 205.0, 220.0, 240.0]:
		var ticks := physics.metres_to_ticks(metres)
		state.apply_sample([ticks, ticks, 0, 0], int(metres * 80.0))
		controller.progress_updated.emit(state)
	assert_eq(int(audio.cue_counts.get("cloche", 0)), 1, "une seule cloche, aux 50 derniers metres")


func test_la_cloche_sonne_aussi_aux_dernieres_secondes_d_une_course_en_temps() -> void:
	# docs/04 §6. Une course en temps n'a pas de metres : la cloche n'y sonnait
	# JAMAIS, et le public n'avait aucune annonce de la fin — alors qu'en
	# distance il en avait une. C'est le meme evenement, il se dit dans les deux
	# modes.
	var rig := _rig()
	var controller: AppController = rig[0]
	var audio: RaceAudio = rig[1]
	var config := RaceConfig.new()
	config.mode = RaceConfig.Mode.TIME
	config.duration_s = 60.0
	controller.race_state_changed.emit(RaceEngine.State.IDLE, RaceEngine.State.ARMING)
	controller.race_state_changed.emit(RaceEngine.State.COUNTDOWN, RaceEngine.State.RUNNING)

	var state := RaceState.new(config)
	var physics := Physics.new(config.roller_mm)
	var ticks := 0
	for second: int in [10, 30, 45, 52, 56]:
		ticks = physics.metres_to_ticks(float(second) * 12.0)
		state.apply_sample([ticks, ticks, 0, 0], second * 1000)
		controller.progress_updated.emit(state)
	assert_eq(int(audio.cue_counts.get("cloche", 0)), 1, "une seule cloche, aux dernieres secondes")


func test_la_poursuite_n_a_pas_de_cloche() -> void:
	# La fin y arrive quand l'ecart se referme : rien ne permet de l'annoncer.
	var rig := _rig()
	var controller: AppController = rig[0]
	var audio: RaceAudio = rig[1]
	var config := RaceConfig.new()
	config.mode = RaceConfig.Mode.PURSUIT
	config.gap_m = 50.0
	controller.race_state_changed.emit(RaceEngine.State.IDLE, RaceEngine.State.ARMING)
	controller.race_state_changed.emit(RaceEngine.State.COUNTDOWN, RaceEngine.State.RUNNING)

	var state := RaceState.new(config)
	var physics := Physics.new(config.roller_mm)
	for metres: float in [50.0, 150.0, 400.0]:
		var lead := physics.metres_to_ticks(metres)
		state.apply_sample([lead, physics.metres_to_ticks(metres * 0.6), 0, 0], int(metres * 80.0))
		controller.progress_updated.emit(state)
	assert_eq(int(audio.cue_counts.get("cloche", 0)), 0, "aucune cloche en poursuite")


func test_la_cloche_ne_sonne_pas_des_la_ligne_de_depart() -> void:
	# LA COMBINAISON DEGENEREE. La cloche annonce la fin imminente aux
	# cinquante derniers metres — or la distance MINIMALE d'une course est
	# cinquante metres. Sur une course de 50 m, elle sonnait donc sur la ligne
	# de depart, et sur une course de 60 m au dixieme de seconde suivant. Une
	# annonce de fin qui tombe au depart ne dit plus rien.
	var rig := _rig()
	var controller: AppController = rig[0]
	var audio: RaceAudio = rig[1]
	var config := RaceConfig.new()
	config.mode = RaceConfig.Mode.DISTANCE
	config.distance_m = 50.0
	controller.race_state_changed.emit(RaceEngine.State.IDLE, RaceEngine.State.ARMING)
	controller.race_state_changed.emit(RaceEngine.State.COUNTDOWN, RaceEngine.State.RUNNING)

	var state := RaceState.new(config)
	var physics := Physics.new(config.roller_mm)
	state.apply_sample([physics.metres_to_ticks(1.0), 0, 0, 0], 200)
	controller.progress_updated.emit(state)
	assert_eq(int(audio.cue_counts.get("cloche", 0)), 0, "rien au premier metre")

	# Elle sonne quand meme, mais dans le DERNIER QUART de l'epreuve.
	state.apply_sample([physics.metres_to_ticks(45.0), 0, 0, 0], 4000)
	controller.progress_updated.emit(state)
	assert_eq(int(audio.cue_counts.get("cloche", 0)), 1, "et une fois pres de la ligne")


func test_la_cloche_ne_sonne_pas_au_depart_d_une_course_en_temps_courte() -> void:
	# Meme piege : la duree minimale est de dix secondes, et la cloche sonne aux
	# dix dernieres.
	var rig := _rig()
	var controller: AppController = rig[0]
	var audio: RaceAudio = rig[1]
	var config := RaceConfig.new()
	config.mode = RaceConfig.Mode.TIME
	config.duration_s = 10.0
	controller.race_state_changed.emit(RaceEngine.State.IDLE, RaceEngine.State.ARMING)
	controller.race_state_changed.emit(RaceEngine.State.COUNTDOWN, RaceEngine.State.RUNNING)

	var state := RaceState.new(config)
	var physics := Physics.new(config.roller_mm)
	state.apply_sample([physics.metres_to_ticks(2.0), 0, 0, 0], 500)
	controller.progress_updated.emit(state)
	assert_eq(int(audio.cue_counts.get("cloche", 0)), 0, "rien a la premiere demi-seconde")

	state.apply_sample([physics.metres_to_ticks(100.0), 0, 0, 0], 9000)
	controller.progress_updated.emit(state)
	assert_eq(int(audio.cue_counts.get("cloche", 0)), 1, "et une fois vers la fin")


func test_le_volume_se_regle_meme_son_coupe() -> void:
	# docs/04 §6 : « la coupure ET le volume sont persistes : ils se reglent la
	# VEILLE, une fois ». Or le curseur etait desactive tant que le son etait
	# coupe — et le son est coupe par defaut. Pour preparer le volume la veille,
	# il fallait donc activer le son, donc faire du bruit : exactement ce que
	# l'operateur cherche a eviter dans une salle vide, et exactement ce que la
	# consigne de ce projet interdit.
	var controller := AppController.new()
	controller.preferences_enabled = false
	add_child_autofree(controller)
	var audio := RaceAudio.new()
	add_child_autofree(audio)
	audio.setup(controller)
	assert_true(audio.is_muted(), "coupe par defaut")

	audio.set_volume_db(-18.0)
	assert_almost_eq(
		controller.settings.audio_volume_db, -18.0, 0.001,
		"le reglage se prend et se persiste sans decouper le son"
	)
	assert_true(audio.is_muted(), "et le son reste coupe")
	audio.set_volume_db(0.0)


## Energie d'un flux sous et au-dessus d'une coupure, par filtre a un pole.
## Grossier — on cherche un ordre de grandeur, pas une analyse de laboratoire.
func _audible_share(stream: AudioStreamWAV, cutoff: float = 200.0) -> float:
	var frames := _frames(stream)
	var alpha := 1.0 - exp(-TAU * cutoff / SoundForge.MIX_RATE)
	var low := 0.0
	var energy_low := 0.0
	var energy_high := 0.0
	for i: int in range(frames):
		var sample := float(stream.data.decode_s16(i * 2)) / 32768.0
		low += alpha * (sample - low)
		energy_low += low * low
		energy_high += (sample - low) * (sample - low)
	return energy_high / maxf(energy_low + energy_high, 1e-9)


func test_tout_son_continu_existe_sur_un_haut_parleur_d_ordinateur() -> void:
	# docs/04 §6, REGLE DES HAUT-PARLEURS. La premiere nappe empilait 55, 82,5,
	# 110 et 165 Hz : mesuree, elle placait 90 % de son energie sous 200 Hz,
	# c'est-a-dire sous ce qu'un haut-parleur d'ordinateur portable restitue.
	# Elle n'existait pas sur les machines qui font tourner ce logiciel, et il
	# ne restait que le vent — « il ne se passe rien ». Un son qu'on ne peut
	# pas entendre n'est pas un son discret, c'est un son absent.
	#
	# Le lit sonore est le seul a jouer en continu : c'est lui qui doit tenir
	# les vingt secondes ou il n'arrive rien, donc c'est sur lui que la regle
	# compte.
	for entry: Array in [
		["nappe", SoundForge.drone()],
		["vent", SoundForge.wind()],
		["rouleaux", SoundForge.rollers()],
		["rumeur", SoundForge.crowd_bed()],
	]:
		var share := _audible_share(entry[1] as AudioStreamWAV)
		assert_gt(
			share, 0.5,
			"« %s » : %.0f %% de son energie au-dessus de 200 Hz" % [entry[0], share * 100.0]
		)


## Niveau atteint a une fraction donnee d'un flux, sur 200 ms.
func _level_at(stream: AudioStreamWAV, fraction: float) -> float:
	var start := int(float(_frames(stream)) * fraction)
	var level := 0.0
	for k: int in range(start, mini(start + SoundForge.MIX_RATE / 5, _frames(stream))):
		level = maxf(level, absf(float(stream.data.decode_s16(k * 2)) / 32768.0))
	return level


## Attend des images de RENDU. Le remix vertical et l'effacement du lit vivent
## dans `_process` : `wait_physics_frames` n'en declenche aucun, et les niveaux
## restaient a leur valeur de construction — le test lisait alors le montage,
## pas le mixage.
func _idle_frames(count: int) -> void:
	for i: int in range(count):
		await get_tree().process_frame


## Compte les FRAPPES d'un flux : les montées franches du niveau, espacées
## d'au moins 150 ms pour ne compter qu'une fois chaque coup.
func _onsets(stream: AudioStreamWAV) -> int:
	# FENETRE LONGUE, 50 ms. Les partiels d'une cloche sont doubles et
	# legerement desaccordes : ils BATTENT l'un contre l'autre, et c'est ce
	# battement qui fait entendre du bronze. Sur une fenetre de 5 ms il
	# ressemblait a une suite de frappes — le detecteur en comptait douze sur
	# un glas qui n'en a qu'une, et accusait un son parfaitement juste.
	var window := SoundForge.MIX_RATE / 20
	var levels: Array[float] = []
	var i := 0
	while i + window < _frames(stream):
		var peak := 0.0
		for k: int in range(i, i + window):
			peak = maxf(peak, absf(float(stream.data.decode_s16(k * 2)) / 32768.0))
		levels.append(peak)
		i += window
	var ceiling := 0.0
	for level: float in levels:
		ceiling = maxf(ceiling, level)
	# La toute premiere fenetre EST une attaque : un flux qui commence par du
	# son commence par une frappe. L'oublier faisait compter zero coup au glas,
	# qui n'en a qu'un — et le test aurait accuse un son parfaitement juste.
	var onsets := 1 if not levels.is_empty() and levels[0] > ceiling * 0.2 else 0
	var rest := 5
	for k: int in range(1, levels.size()):
		rest = maxi(0, rest - 1)
		# Une frappe : le niveau bondit de moitie et depasse un cinquieme du
		# maximum du flux. Le repos evite de compter la meme deux fois.
		if rest == 0 and levels[k] > levels[k - 1] * 1.8 and levels[k] > ceiling * 0.25:
			onsets += 1
			rest = 5
	return onsets


func test_la_cloche_est_une_volee_et_non_un_coup() -> void:
	# docs/04 §6 : sur piste, la fin se dit a la cloche AGITEE. Un coup unique
	# se prend pour un bip — c'est le reproche fait a la premiere version.
	var peal := SoundForge.bell()
	assert_gte(_onsets(peal), 3, "la cloche sonne en volee")
	assert_gt(_frames(peal), SoundForge.MIX_RATE * 2, "et elle dure, comme une vraie")
	# Le glas, lui, est UN coup : c'est ce qui le distingue a l'oreille.
	assert_eq(_onsets(SoundForge.knell()), 1, "le glas ne sonne qu'une fois")


func test_la_clameur_d_arrivee_est_autre_chose_qu_une_reaction() -> void:
	# « une foule qui hurle a l'arrivee » : le moment de la soiree. La petite
	# clameur des faits de course ne peut pas le porter — elle dure une seconde
	# et demie et retombe aussitot.
	var roar := SoundForge.roar()
	var cheer := SoundForge.crowd()
	assert_gt(_frames(roar), _frames(cheer) * 2, "elle dure bien plus longtemps")
	# Et elle TIENT : au tiers de sa duree elle est encore a plein regime, la
	# ou la petite clameur est deja passee. C'est ce plateau qui fait la
	# difference entre une salle qui reagit et une salle qui explose.
	#
	# Compare a SON PROPRE maximum, et non a une valeur absolue : la clameur est
	# faite de centaines de voix qui se superposent au hasard, si bien que son
	# echantillon le plus fort est une coincidence et non son niveau utile. Un
	# seuil absolu mesurait cette coincidence.
	assert_gt(_level_at(roar, 1.0 / 3.0), _peak(roar) * 0.4, "au tiers, la salle hurle encore")
	assert_lt(_level_at(cheer, 1.0 / 3.0 + 0.5), _peak(cheer) * 0.4, "la petite est deja passee")


func test_les_trois_couches_de_musique_restent_en_phase() -> void:
	# Remix vertical : elles tournent ENSEMBLE et seul leur volume change. La
	# moindre difference de longueur les ferait glisser l'une sur l'autre en
	# quelques secondes — deux mesures plus tard la batterie ne tomberait plus
	# sur la basse.
	var layers := [MusicForge.pulse(), MusicForge.drive(), MusicForge.lead()]
	for layer: AudioStreamWAV in layers:
		assert_eq(layer.loop_mode, AudioStreamWAV.LOOP_FORWARD, "chaque couche boucle")
		assert_eq(_frames(layer), _frames(layers[0]), "et toutes ont la meme longueur")
		assert_eq(layer.loop_end, _frames(layer), "la boucle couvre tout le flux")
	assert_almost_eq(
		float(_frames(layers[0])) / SoundForge.MIX_RATE, MusicForge.LOOP_S, 0.001,
		"deux mesures a 150 a la noire"
	)
	# La pulsation a un coup par temps : c'est elle qui donne le tempo.
	assert_gte(_onsets(layers[0]), MusicForge.BEATS, "un coup de grosse caisse par temps")


func test_la_musique_monte_avec_la_course_et_passe_au_complet_a_la_cloche() -> void:
	var rig := _rig()
	var controller: AppController = rig[0]
	var audio: RaceAudio = rig[1]
	var config := RaceConfig.new()
	config.mode = RaceConfig.Mode.DISTANCE
	config.distance_m = 400.0
	controller.race_state_changed.emit(RaceEngine.State.IDLE, RaceEngine.State.ARMING)
	controller.race_state_changed.emit(RaceEngine.State.COUNTDOWN, RaceEngine.State.RUNNING)
	assert_eq(audio.last_cue, "musique", "la musique part avec la course")

	var state := RaceState.new(config)
	var physics := Physics.new(config.roller_mm)
	# Debut de course, allure faible : la pulsation seule.
	state.apply_sample([physics.metres_to_ticks(4.0), 0, 0, 0], 4000)
	controller.progress_updated.emit(state)
	await _idle_frames(3)
	var quiet: Dictionary = audio.music_levels()
	assert_lt(float(quiet["lead"]), -50.0, "le theme se tait tant qu'il ne se passe rien")

	# Derniers metres, mais A FAIBLE ALLURE : c'est la CLOCHE qui doit faire
	# entrer le theme, pas la vitesse. Un leader rapide aurait ouvert la couche
	# de lui-meme, et le test aurait affirme prouver un mecanisme qu'il ne
	# touchait pas — verifie en le retirant.
	var ticks := physics.metres_to_ticks(370.0)
	state.apply_sample([ticks, 0, 0, 0], 300000)
	controller.progress_updated.emit(state)
	await _idle_frames(3)
	assert_eq(int(audio.cue_counts.get("cloche", 0)), 1, "la cloche a sonne")
	var full: Dictionary = audio.music_levels()
	assert_gt(float(full["lead"]), -30.0, "le theme entre pour la fin")
	assert_gt(float(full["drive"]), float(quiet["drive"]), "et la batterie avec lui")


func test_une_annonce_efface_le_lit_puis_il_remonte() -> void:
	# Sans cela, la cloche se noie dans le fond qu'elle est censee interrompre.
	var rig := _rig()
	var controller: AppController = rig[0]
	var audio: RaceAudio = rig[1]
	controller.race_state_changed.emit(RaceEngine.State.IDLE, RaceEngine.State.ARMING)
	controller.race_state_changed.emit(RaceEngine.State.COUNTDOWN, RaceEngine.State.RUNNING)
	assert_eq(audio.duck_db(), 0.0, "rien n'efface le lit tant qu'on n'annonce rien")

	controller.rider_eliminated.emit(0, 2, 50.0)
	assert_eq(int(audio.cue_counts.get("glas", 0)), 1, "l'elimination a son glas")
	assert_almost_eq(audio.duck_db(), RaceAudio.DUCK_DB, 0.01, "le lit plonge sous lui")

	await _idle_frames(240)
	assert_eq(audio.duck_db(), 0.0, "puis il revient tout seul")


func test_chaque_enregistrement_est_present_et_lisible() -> void:
	# Trois sons seulement viennent d'enregistrements — la cloche et les deux
	# reactions de foule — parce que la synthese les rend mal : « du bruit
	# blanc » et « plein de bips ». Le reste est synthetise, et doit le rester :
	# rien de fige ne peut suivre la vitesse ni boucler en phase.
	for key: String in RaceAudio.SAMPLES:
		var path: String = RaceAudio.SAMPLES[key]
		assert_true(ResourceLoader.exists(path), "« %s » est dans le depot" % key)
		var stream := ResourceLoader.load(path) as AudioStream
		assert_not_null(stream, "« %s » se charge" % key)
		assert_gt(stream.get_length(), 1.0, "« %s » n'est pas un fichier vide" % key)


func test_un_enregistrement_manquant_ne_fait_pas_taire_le_logiciel() -> void:
	# Un export mal ficele, un fichier corrompu, une plateforme qui n'importe
	# pas le Vorbis — et l'ecran public passerait une soiree entiere muet sur
	# ses trois sons les plus attendus. La synthese reste derriere chacun.
	var fallback := SoundForge.bell()
	var missing := RaceAudio.SAMPLES.duplicate()
	assert_true(missing.has("cloche"), "la cle existe bien")
	# On ne peut pas supprimer un fichier du depot depuis un test ; on eprouve
	# donc le chemin de repli sur une cle dont le fichier n'existe pas.
	assert_eq(
		RaceAudio.sampled_or("res://audio/samples/absent.ogg", fallback), fallback,
		"un chemin absent rend la synthese"
	)
	assert_ne(
		RaceAudio.sampled_or(RaceAudio.SAMPLES["cloche"], fallback), fallback,
		"et un chemin present rend l'enregistrement"
	)


func test_chaque_enregistrement_est_credite_et_sans_partage_a_l_identique() -> void:
	# docs/04 §6 : CC0, domaine public ou CC-BY, jamais CC BY-SA. Une clause SA
	# suivrait le fichier modifie dans toute distribution du logiciel, et cela
	# ne se decide pas au detour d'un choix de bruitage.
	var file := FileAccess.open("res://audio/CREDITS.md", FileAccess.READ)
	assert_not_null(file, "le fichier de credits existe")
	var lines := file.get_as_text().split("\n")
	for key: String in RaceAudio.SAMPLES:
		var name: String = str(RaceAudio.SAMPLES[key]).get_file()
		var row := ""
		for line: String in lines:
			if line.begins_with("|") and line.contains(name):
				row = line
		assert_false(row.is_empty(), "« %s » a sa ligne dans le tableau" % name)
		# LA LIGNE DU FICHIER, pas le document. Chercher « BY-SA » partout
		# interdisait d'EXPLIQUER pourquoi cette clause est ecartee — et la
		# garde accusait le paragraphe qui la refuse. Une garde ne doit pas
		# rendre impossible d'ecrire ce qu'elle defend.
		assert_false(row.contains("BY-SA"), "« %s » : pas de partage a l'identique" % name)
		assert_false(row.contains("ShareAlike"), "« %s » : ni sous son autre nom" % name)
		assert_true(
			row.contains("CC0") or row.contains("omaine public") or row.contains("CC BY"),
			"« %s » : une licence permissive, nommee" % name
		)


func test_le_podium_a_sa_musique_et_l_abandon_ne_l_a_pas() -> void:
	# La musique de course est mineure et ne se resout jamais : de la tension
	# qui ne retombe pas, ce qu'on veut SOUS une course. Un podium demande
	# l'inverse — une resolution. D'ou une autre musique, en majeur et plus
	# lente, qui entre SOUS la clameur : attendre qu'elle finisse laisserait un
	# trou de quatre secondes a l'instant ou le classement s'affiche.
	var rig := _rig()
	var controller: AppController = rig[0]
	var audio: RaceAudio = rig[1]
	controller.race_state_changed.emit(RaceEngine.State.IDLE, RaceEngine.State.ARMING)
	controller.race_state_changed.emit(RaceEngine.State.COUNTDOWN, RaceEngine.State.RUNNING)
	controller.race_finished.emit(RaceResult.new())
	assert_eq(int(audio.cue_counts.get("podium", 0)), 1, "le podium a sa musique")
	assert_eq(int(audio.cue_counts.get("clameur", 0)), 1, "et la salle hurle par-dessus")

	# Elle se tait au decompte suivant, sans quoi elle se superposerait a lui.
	controller.race_state_changed.emit(RaceEngine.State.RESULTS, RaceEngine.State.ARMING)
	assert_false(audio.podium_playing(), "l'hymne s'arrete devant la course suivante")

	# UNE COURSE ABANDONNEE N'A PAS DE PODIUM. Une fanfare de victoire sur un
	# abandon serait grotesque, et l'abandon ramene le moteur a IDLE.
	controller.race_state_changed.emit(RaceEngine.State.IDLE, RaceEngine.State.ARMING)
	controller.race_state_changed.emit(RaceEngine.State.COUNTDOWN, RaceEngine.State.RUNNING)
	controller.race_state_changed.emit(RaceEngine.State.RUNNING, RaceEngine.State.IDLE)
	assert_false(audio.podium_playing(), "rien ne joue apres un abandon")
	assert_eq(int(audio.cue_counts.get("podium", 0)), 0, "et aucun hymne n'a ete lance")


func test_l_hymne_du_podium_boucle_et_resout_en_majeur() -> void:
	var anthem := MusicForge.anthem()
	assert_eq(anthem.loop_mode, AudioStreamWAV.LOOP_FORWARD, "le classement reste, la musique aussi")
	# Quatre mesures et non deux : le podium tient parfois une minute a l'ecran,
	# et une boucle courte s'entendrait comme une boucle.
	assert_almost_eq(
		float(_frames(anthem)) / SoundForge.MIX_RATE,
		MusicForge.ANTHEM_BEAT_S * float(MusicForge.ANTHEM_BARS) * 4.0, 0.001,
		"quatre mesures a 100 a la noire"
	)
	assert_gt(
		float(_frames(anthem)) / SoundForge.MIX_RATE, MusicForge.LOOP_S,
		"plus longue que la musique de course"
	)


func test_la_salle_ne_hurle_pas_pour_du_bruit_de_mesure() -> void:
	# Une course de vingt secondes produisait DIX clameurs — une toutes les
	# deux secondes et demie, du depart a l'arrivee. Une salle qui hurle sans
	# discontinuer ne hurle plus.
	#
	# Deux causes, toutes deux du bruit pris pour un fait de course. Les trames
	# arrivent a 20 Hz : sur cinq centiemes de seconde, un demi-km/h de gigue
	# du lissage donne dix km/h par seconde, le seuil exact de la clameur. Et
	# deux coureurs cote a cote echangent leurs places a chaque trame, ce qui
	# passait pour un depassement.
	var rig := _rig()
	var controller: AppController = rig[0]
	var audio: RaceAudio = rig[1]
	var config := RaceConfig.new()
	config.mode = RaceConfig.Mode.DISTANCE
	config.distance_m = 500.0
	config.active_riders = [0, 1]
	controller.race_state_changed.emit(RaceEngine.State.IDLE, RaceEngine.State.ARMING)
	controller.race_state_changed.emit(RaceEngine.State.COUNTDOWN, RaceEngine.State.RUNNING)

	var state := RaceState.new(config)
	var physics := Physics.new(config.roller_mm)
	# Coude a coude a allure constante, trente trames a 20 Hz : les deux
	# s'echangent la tete sans arret, personne ne prend le moindre metre.
	for step: int in range(30):
		var metres := 10.0 + float(step) * 0.6
		var other := metres + (0.15 if step % 2 == 0 else -0.15)
		state.apply_sample(
			[physics.metres_to_ticks(metres), physics.metres_to_ticks(other), 0, 0],
			1000 + step * 50
		)
		controller.progress_updated.emit(state)
	assert_eq(int(audio.cue_counts.get("souffle", 0)), 0, "cote a cote n'est pas un depassement")
	assert_lte(int(audio.cue_counts.get("foule", 0)), 1, "et la salle reste calme")

	# UN VRAI depassement, lui, s'entend : le second prend dix metres.
	state.apply_sample(
		[physics.metres_to_ticks(30.0), physics.metres_to_ticks(40.0), 0, 0], 4000
	)
	controller.progress_updated.emit(state)
	assert_eq(int(audio.cue_counts.get("souffle", 0)), 1, "dix metres, c'est un depassement")


func test_lien_perdu_le_lit_s_efface_et_ne_remonte_qu_avec_les_trames() -> void:
	# docs/04 §6. Les trames n'arrivent plus, donc l'intensite non plus : elle
	# restait a sa derniere valeur, et rouleaux, vent, nappe continuaient comme
	# si l'on pedalait sous un ecran fige au bandeau LIEN PERDU. Mesure : memes
	# niveaux deux secondes apres la coupure.
	var rig := _rig()
	var controller: AppController = rig[0]
	var audio: RaceAudio = rig[1]
	var config := RaceConfig.new()
	config.mode = RaceConfig.Mode.DISTANCE
	config.distance_m = 2000.0
	controller.race_state_changed.emit(RaceEngine.State.IDLE, RaceEngine.State.ARMING)
	controller.race_state_changed.emit(RaceEngine.State.COUNTDOWN, RaceEngine.State.RUNNING)
	var state := RaceState.new(config)
	var physics := Physics.new(config.roller_mm)
	# 12,5 m/s — 45 km/h : le lit est a pleine intensite.
	for metres: float in [100.0, 200.0, 300.0, 400.0, 500.0]:
		var ticks := physics.metres_to_ticks(metres)
		state.apply_sample([ticks, ticks, 0, 0], int(metres * 80.0))
		controller.progress_updated.emit(state)
	await get_tree().process_frame
	var before: Dictionary = audio.bed_levels()
	assert_gt(float(audio.music_levels()["lead"]), -30.0, "a 45 km/h la couche de tete joue")
	assert_gt(float(before["rollers"]), -15.0, "et les rouleaux sifflent")

	controller.link_state_changed.emit(Protocol.State.LINK_LOST)
	for i: int in range(3):
		await get_tree().process_frame
	var lost: Dictionary = audio.bed_levels()
	assert_lt(float(lost["rollers"]), float(before["rollers"]) - 10.0, "les rouleaux retombent")
	assert_lt(float(lost["wind"]), float(before["wind"]) - 10.0, "le vent aussi")
	assert_eq(float(audio.music_levels()["lead"]), -60.0, "la couche de tete se tait")
	assert_eq(float(audio.music_levels()["drive"]), -60.0, "la couche de rythme aussi")
	assert_gt(float(audio.music_levels()["pulse"]), -20.0, "seul le pouls reste : pas finie")

	# Le lien revient : rien ne remonte tant que les trames ne reviennent pas.
	controller.link_state_changed.emit(Protocol.State.IDENTIFIED)
	await get_tree().process_frame
	assert_eq(float(audio.music_levels()["lead"]), -60.0, "le lien seul ne suffit pas")
	for metres: float in [600.0, 700.0, 800.0]:
		var ticks := physics.metres_to_ticks(metres)
		state.apply_sample([ticks, ticks, 0, 0], int(metres * 80.0))
		controller.progress_updated.emit(state)
	await get_tree().process_frame
	assert_gt(float(audio.music_levels()["lead"]), -30.0, "les trames reviennent, le lit remonte")
	# Le plongeon de l'annonce se relache encore : on mesure la remontee par
	# rapport au niveau coupe, pas dans l'absolu.
	assert_gt(float(audio.bed_levels()["rollers"]), float(lost["rollers"]) + 5.0, "les rouleaux aussi")
