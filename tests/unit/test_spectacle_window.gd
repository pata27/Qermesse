## La fenetre spectacle — docs/04, budget de performance.
extends GutTest


func test_la_3d_ne_se_rend_jamais_plus_fin_que_le_projecteur() -> void:
	assert_almost_eq(SpectacleWindow.render_factor_for(Vector2i(1920, 1080)), 1.0, 0.001)
	# 720p : 2,25x moins de pixels que le 1080p de la composition.
	assert_almost_eq(SpectacleWindow.render_factor_for(Vector2i(1280, 720)), 0.6667, 0.001)
	# Un 4K ne fait pas depasser le budget : le rendu reste en 1080p.
	assert_almost_eq(SpectacleWindow.render_factor_for(Vector2i(3840, 2160)), 1.0, 0.001)
	# Plancher : une fenetre minuscule ne rend pas une bouillie.
	assert_almost_eq(SpectacleWindow.render_factor_for(Vector2i(160, 90)), 0.25, 0.001)

