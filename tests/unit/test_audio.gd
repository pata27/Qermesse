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
