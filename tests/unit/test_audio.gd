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
