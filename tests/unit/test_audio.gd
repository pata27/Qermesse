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
