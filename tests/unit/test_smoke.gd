# Test temoin du jalon J0 : prouve que la chaine headless fonctionne de bout en
# bout — Godot demarre, GUT charge, un test s'execute, le processus sort en 0.
#
# Il ne teste rien du produit et n'a pas vocation a grossir. Le vrai contenu
# arrive au lot 2 (docs/05).
extends GutTest


func test_la_chaine_headless_fonctionne() -> void:
	assert_eq(2 + 2, 4, "l'arithmetique tient encore")


func test_les_constantes_physiques_de_docs_01_sont_coherentes() -> void:
	# Non-regression v1/v2 : 100 m avec un rouleau de 114.3 mm = 278 ticks.
	# La vraie implementation arrive dans core/physics.gd au lot 2 ; ce calcul
	# en dur verifie surtout que le chiffre de docs/01 §7 est le bon.
	var circumference_mm: float = 114.3 * PI
	var ticks: int = int(floor(100.0 * 1000.0 / circumference_mm))
	assert_eq(ticks, 278, "100 m @ rouleau 114.3 mm")
