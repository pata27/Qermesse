## Le moniteur de budget de rendu — docs/04 §4.
##
## Il gardait toutes les images depuis le lancement : un flottant par image,
## toute la soiree, et deux compteurs jamais relus. Ce qu'on protege ici : la
## fenetre glissante, et la regle « on ne degrade pas sur un hoquet ».
extends GutTest


func test_le_moniteur_ne_garde_que_la_derniere_minute() -> void:
	var perf := PerfMonitor.new()
	perf.retain_s = 60.0
	# Dix minutes a 60 images par seconde.
	for i: int in range(60 * 600):
		perf.sample(1.0 / 60.0, 60.0)
	assert_lte(perf.sample_count(), 60 * 60 + 1, "au plus une minute d'images")
	assert_gte(perf.sample_count(), 60 * 60 - 1, "et toute la derniere minute")


func test_un_demarrage_lent_ne_pese_plus_sur_le_verdict_une_minute_apres() -> void:
	# Le verdict porte sur ce qui vient de se passer. Cinq secondes a 30 fps au
	# chargement, puis une minute tenue : le budget est tenu.
	var perf := PerfMonitor.new()
	perf.retain_s = 60.0
	for i: int in range(30 * 5):
		perf.sample(1.0 / 30.0, 30.0)
	assert_false(perf.budget_met(), "juste apres le demarrage, non tenu")
	for i: int in range(60 * 61):
		perf.sample(1.0 / 60.0, 60.0)
	assert_true(perf.budget_met(), "une minute plus tard, les images lentes sont sorties")
	assert_almost_eq(perf.min_fps(), 60.0, 0.001)


func test_on_ne_degrade_pas_sur_un_hoquet_mais_sur_une_fenetre_entiere() -> void:
	var perf := PerfMonitor.new()
	var triggered := false
	# 2,9 s sous le seuil, une image au-dessus, 2,9 s sous : jamais trois
	# secondes d'affilee.
	for round: int in range(2):
		for i: int in range(int(2.9 * 30.0)):
			triggered = triggered or perf.sample(1.0 / 30.0, 30.0)
		triggered = triggered or perf.sample(1.0 / 60.0, 60.0)
	assert_false(triggered, "des hoquets, pas une fenetre : on ne degrade pas")
	var fired := 0
	for i: int in range(int(3.1 * 30.0)):
		if perf.sample(1.0 / 30.0, 30.0):
			fired += 1
	assert_eq(fired, 1, "trois secondes d'affilee : une seule decision")
