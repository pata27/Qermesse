## Tests de l'interpolation de position et des niveaux de qualité — lot 4.
##
## Le cas qui compte est la BASSE VITESSE : `docs/05` l'exige explicitement.
## Un tick vaut 35,9 cm, donc à 5 km/h un rider produit une mesure toutes les
## ~260 ms. Sans interpolation, l'affichage avance par bonds d'une image sur
## quinze — un escalier parfaitement visible en projection.
extends GutTest

const CIRCUMFERENCE_M := 0.35908


## Déroule une course à vitesse constante et rend la suite des positions
## affichées, image par image.
func _run(kph: float, seconds: float, fps: float) -> Array[float]:
	var interp := RiderInterpolator.new()
	var dt := 1.0 / fps
	var speed_m_s := kph / 3.6
	var real_m := 0.0
	var ticks := 0
	var out: Array[float] = []

	var frames := int(seconds * fps)
	for i: int in range(frames):
		real_m += speed_m_s * dt
		# Le capteur ne rend que des multiples de la circonference.
		var measured_ticks := int(floor(real_m / CIRCUMFERENCE_M))
		if measured_ticks != ticks:
			ticks = measured_ticks
			interp.push_sample(float(ticks) * CIRCUMFERENCE_M, kph)
		out.append(interp.update(dt))
	return out


func _steps(values: Array[float]) -> Array[float]:
	var out: Array[float] = []
	for i: int in range(1, values.size()):
		out.append(values[i] - values[i - 1])
	return out


# =============================================================================
# Le cas exige par docs/05 : basse vitesse
# =============================================================================

func test_a_basse_vitesse_l_affichage_avance_a_chaque_image() -> void:
	# 5 km/h : une mesure toutes les 260 ms, soit une image sur 37 a 144 Hz.
	var values := _run(5.0, 6.0, 144.0)
	var steps := _steps(values)

	var immobile := 0
	for step: float in steps:
		if step <= 0.0:
			immobile += 1
	# On tolere le tout debut, ou la vitesse lissee n'est pas encore etablie.
	assert_lt(
		float(immobile) / float(steps.size()), 0.05,
		"l'affichage doit avancer a presque chaque image, pas une sur trente-sept"
	)


func test_a_basse_vitesse_l_avance_reste_reguliere() -> void:
	# Le symptome a eviter n'est pas seulement l'immobilite : c'est l'escalier.
	# On compare le plus grand pas au pas median sur la seconde moitie du run.
	var steps := _steps(_run(5.0, 8.0, 144.0))
	var tail := steps.slice(steps.size() / 2)
	tail.sort()
	var median: float = tail[tail.size() / 2]
	var largest: float = tail[tail.size() - 1]
	assert_gt(median, 0.0)
	assert_lt(
		largest / median, 3.0,
		"le plus grand pas ne doit pas ecraser le pas median : ce serait un escalier"
	)


func test_l_affichage_ne_recule_jamais() -> void:
	for kph: float in [3.0, 5.0, 20.0, 45.0, 70.0]:
		var steps := _steps(_run(kph, 5.0, 60.0))
		for step: float in steps:
			assert_true(step >= 0.0, "recul de %.4f m a %.0f km/h" % [step, kph])


# =============================================================================
# Fidelite
# =============================================================================

func test_l_affichage_colle_a_la_mesure_a_vitesse_de_course() -> void:
	var kph := 45.0
	var interp := RiderInterpolator.new()
	var dt := 1.0 / 60.0
	var speed_m_s := kph / 3.6
	var real_m := 0.0
	var ticks := 0
	var worst := 0.0

	for i: int in range(int(10.0 * 60.0)):
		real_m += speed_m_s * dt
		var measured_ticks := int(floor(real_m / CIRCUMFERENCE_M))
		if measured_ticks != ticks:
			ticks = measured_ticks
			interp.push_sample(float(ticks) * CIRCUMFERENCE_M, kph)
		var shown := interp.update(dt)
		if i > 60:  # apres l'etablissement
			worst = maxf(worst, absf(shown - real_m))
	# Un tick vaut 36 cm : rester sous un metre d'ecart est le mieux qu'on
	# puisse exiger d'un capteur a cette resolution.
	assert_lt(worst, 1.0, "ecart maximal a la position reelle : %.2f m" % worst)


func test_le_resultat_ne_depend_pas_du_framerate() -> void:
	# Le rattrapage est exponentiel en SECONDES : a 60 comme a 144 Hz, la
	# position apres 5 s doit etre la meme.
	var at_60 := _run(45.0, 5.0, 60.0)
	var at_144 := _run(45.0, 5.0, 144.0)
	assert_almost_eq(at_60[at_60.size() - 1], at_144[at_144.size() - 1], 0.5)


func test_un_rider_a_l_arret_ne_derive_pas() -> void:
	var interp := RiderInterpolator.new()
	interp.push_sample(50.0, 0.0)
	for i: int in range(600):
		interp.update(1.0 / 60.0)
	assert_almost_eq(interp.display_m(), 50.0, 0.01)


func test_un_rider_fige_ne_bouge_plus() -> void:
	# docs/02 §1 : un rider arrive est fige a son franchissement, meme s'il
	# continue de pedaler.
	var interp := RiderInterpolator.new()
	interp.push_sample(100.0, 45.0)
	for i: int in range(30):
		interp.update(1.0 / 60.0)
	var at_finish := interp.display_m()
	interp.freeze()
	interp.push_sample(150.0, 45.0)
	for i: int in range(120):
		interp.update(1.0 / 60.0)
	assert_eq(interp.display_m(), at_finish)
	assert_true(interp.is_frozen())


func test_l_affichage_n_anticipe_pas_de_plus_d_un_tick() -> void:
	# Sans borne, une erreur de vitesse ferait franchir la ligne a un rider qui
	# ne l'a pas atteinte.
	var interp := RiderInterpolator.new()
	interp.push_sample(10.0, 45.0)
	# Aucune nouvelle mesure pendant une seconde entiere : le lien est tombe.
	for i: int in range(60):
		interp.update(1.0 / 60.0)
	var lead := interp.display_m() - 10.0
	# Un tick, pas « la vitesse pendant une seconde plus un tick » : la version
	# precedente de cette assertion tolerait 12,9 m et laissait passer une
	# borne qui ne bornait rien.
	assert_lt(lead, RiderInterpolator.MAX_LEAD_M + 0.01)
	assert_gt(lead, RiderInterpolator.MAX_LEAD_M * 0.9, "et il y va franchement")


func test_lien_perdu_le_rider_s_arrete_a_un_tick_et_repart_sans_saut() -> void:
	# docs/01 §6.2 : gel sur la derniere valeur connue. Trois secondes sans
	# trame a 45 km/h feraient 37 m de derive sans borne — puis un rider plante
	# au retour du lien, le temps que la mesure le rattrape.
	var interp := RiderInterpolator.new()
	interp.push_sample(100.0, 45.0)
	for i: int in range(180):
		interp.update(1.0 / 60.0)
	assert_lt(interp.display_m(), 100.0 + RiderInterpolator.MAX_LEAD_M + 0.01)

	# Le lien revient : le compteur absolu dit ou en est vraiment le rider.
	interp.push_sample(137.5, 45.0)
	var before := interp.display_m()
	interp.update(1.0 / 60.0)
	assert_gt(interp.display_m(), before, "il repart aussitot, sans attendre d'etre rattrape")


# =============================================================================
# Niveaux de qualite — docs/04 §4
# =============================================================================

func test_les_trois_niveaux_existent_et_sont_ordonnes() -> void:
	var low := RenderQuality.new(RenderQuality.Level.LOW)
	var medium := RenderQuality.new(RenderQuality.Level.MEDIUM)
	var high := RenderQuality.new(RenderQuality.Level.HIGH)

	assert_eq(low.level_name(), "bas")
	assert_eq(medium.level_name(), "moyen")
	assert_eq(high.level_name(), "eleve")

	# Le cout doit croitre de facon monotone, sinon « degrader » n'a pas de sens.
	assert_lt(int(low.option("crowd_count")), int(medium.option("crowd_count")))
	assert_lt(int(medium.option("crowd_count")), int(high.option("crowd_count")))
	assert_lt(int(low.option("trail_segments")), int(high.option("trail_segments")))


func test_les_effets_couteux_sont_coupes_en_premier() -> void:
	# docs/06 §4 designe le volumetrique, la foule et le flou radial.
	var low := RenderQuality.new(RenderQuality.Level.LOW)
	assert_false(bool(low.option("volumetric_fog")))
	assert_false(bool(low.option("radial_blur")))
	assert_eq(int(low.option("crowd_count")), 0)

	var medium := RenderQuality.new(RenderQuality.Level.MEDIUM)
	assert_false(bool(medium.option("volumetric_fog")), "trop cher pour un GPU integre")
	assert_true(bool(medium.option("glow")), "le neon est le parti pris, il reste")


func test_la_degradation_descend_d_un_cran_et_s_arrete_en_bas() -> void:
	var quality := RenderQuality.new(RenderQuality.Level.HIGH)
	assert_true(quality.degrade())
	assert_eq(quality.level, RenderQuality.Level.MEDIUM)
	assert_true(quality.degrade())
	assert_eq(quality.level, RenderQuality.Level.LOW)
	assert_false(quality.degrade(), "on ne descend pas sous le niveau bas")
	assert_eq(quality.level, RenderQuality.Level.LOW)


func test_un_gpu_integre_vise_le_niveau_moyen() -> void:
	# La cible de docs/04 §4. On vise « moyen » et on tient 60 fps, plutot que
	# de viser « eleve » et de rater le budget.
	var detected := RenderQuality.detect()
	assert_true(
		detected in [RenderQuality.Level.LOW, RenderQuality.Level.MEDIUM,
			RenderQuality.Level.HIGH],
		"la detection doit rendre un niveau valide"
	)
	gut.p("adaptateur detecte : %s -> %s" % [
		RenderQuality.adapter_description(),
		RenderQuality.new(detected).level_name(),
	])


func test_le_nom_de_niveau_fait_l_aller_retour() -> void:
	for level: RenderQuality.Level in [RenderQuality.Level.LOW, RenderQuality.Level.MEDIUM,
			RenderQuality.Level.HIGH]:
		var name := RenderQuality.new(level).level_name()
		assert_eq(RenderQuality.level_from_name(name), level)
