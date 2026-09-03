## Atmosphère de la scène — environnement et lumières, `docs/04` §1, §2 et §4.
##
## Sortie de `race_scene.gd`, qui avait repassé les mille lignes que le linter
## impose. La découpe suit un sujet : tout ce qui règle la LUMIÈRE et l'AIR de
## la salle vit ici — fond anthracite, ambiante, halo, brume, les trois sources
## lumineuses — et rien de ce qui concerne les coureurs, la piste ou l'habillage.
##
## Ce qui dépend du niveau de qualité passe par `apply()` : la scène le rappelle
## à chaque changement de niveau, et `relieve()` allège quand l'écran se scinde.
class_name RaceAmbience
extends Node3D

var _environment: WorldEnvironment
var _key_light: DirectionalLight3D


## Construit l'environnement et les trois lumières.
func build(quality: RenderQuality) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	# Anthracite de docs/04 §2 : le fond ne doit jamais concurrencer les néons.
	env.background_color = Color("#0B0E14")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#1A2030")
	# Ambiante réduite : trop d'ambiante écrase les ombres et rend tout plat.
	env.ambient_light_energy = 0.22

	env.glow_enabled = bool(quality.option("glow"))
	# Bloom modéré : un halo trop généreux ramène toutes les couleurs vers le
	# blanc et annule la distinction entre les couloirs.
	env.glow_intensity = 0.6
	env.glow_bloom = 0.12
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.glow_hdr_threshold = 0.85

	# VOLUMÉTRIQUE LÉGER — et « léger » se mesure (docs/04 §4).
	#
	# À 0,012 de densité avec une albédo blanche par défaut, la brume diffusait
	# les projecteurs de salle dans tout le volume : le fond anthracite montait
	# à une luminance de 75 contre 33 sans elle, les gradins lointains
	# disparaissaient dans un lait gris et les néons perdaient le contraste qui
	# les fait exister (docs/04 §1). Le niveau de qualité le plus coûteux
	# donnait donc l'image la moins conforme.
	#
	# C'EST L'ALBÉDO, PAS LA DENSITÉ. J'ai commencé par diviser la densité par
	# trois : le fond retombait à 32, mais la brume ne se voyait plus du tout —
	# on payait un effet devenu invisible. La mesure a tranché : à albédo
	# sombre, faire varier la densité de 0,004 à 0,012 déplace le fond de 31 à
	# 31,9. L'albédo décide de ce que la brume renvoie des lampes, et blanche
	# par défaut, elle renvoyait tout. Elle passe donc à un bleu de salle et la
	# densité reste entière : la brume enveloppe les gradins sans les effacer,
	# fond mesuré à 35,8 contre 32,9 sans elle.
	#
	# `sky_affect` réduit épargne en plus le fond, qui n'est pas un volume à
	# traverser mais une couleur derrière tout.
	if bool(quality.option("volumetric_fog")):
		env.volumetric_fog_enabled = true
		env.volumetric_fog_density = 0.012
		env.volumetric_fog_albedo = Color("#4A5F80")
		env.volumetric_fog_emission = Color("#101828")
		# Diffusion vers l'avant : la brume se voit autour des lampes plutôt
		# qu'uniformément, ce qui est la façon dont une salle embrumée se lit.
		env.volumetric_fog_anisotropy = 0.35
		env.volumetric_fog_sky_affect = 0.3
	env.fog_enabled = true
	# Légèrement plus claire que le fond : la brume donne de la profondeur et
	# empêche le haut de l'image de tomber dans un noir absolu.
	env.fog_light_color = Color("#141A26")
	env.fog_density = 0.008

	if bool(quality.option("ssao")):
		env.ssao_enabled = true

	_environment = WorldEnvironment.new()
	_environment.environment = env
	add_child(_environment)

	# Deux lumières, et c'est le minimum : un corps ne prend du volume que s'il
	# est ÉCLAIRÉ. Avec une seule source rasante et beaucoup d'ambiante, les
	# cyclistes ressortaient plats.
	var key := DirectionalLight3D.new()
	_key_light = key
	key.name = "KeyLight"
	key.light_energy = 0.62
	key.light_color = Color("#CFE0FF")
	key.rotation_degrees = Vector3(-38.0, 42.0, 0.0)
	key.shadow_enabled = bool(quality.option("shadows"))
	# DEUX CASCADES, PAS QUATRE. Le décor tient dans un couloir d'une
	# cinquantaine de mètres ; les quatre cascades par défaut redessinaient
	# chaque projeteur quatre fois pour une précision que cette profondeur de
	# champ ne réclame pas.
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	key.directional_shadow_max_distance = 55.0
	add_child(key)

	# Contre-jour froid depuis l'arrière : il détache les silhouettes du fond
	# anthracite sans éclaircir la piste.
	var fill := DirectionalLight3D.new()
	fill.name = "FillLight"
	fill.light_energy = 0.30
	fill.light_color = Color("#5A82C4")
	fill.rotation_degrees = Vector3(-12.0, -155.0, 0.0)
	fill.shadow_enabled = false
	add_child(fill)

	# Contre-jour rasant venant de l'avant : il dessine le bord supérieur des
	# cyclistes, qui sans lui se fondaient dans le parquet.
	var rim := DirectionalLight3D.new()
	rim.name = "RimLight"
	rim.light_energy = 0.55
	rim.light_color = Color("#BFD4FF")
	rim.rotation_degrees = Vector3(-8.0, 12.0, 0.0)
	rim.shadow_enabled = false
	add_child(rim)


## L'environnement, pour la scène qui ajuste sa qualité.
func environment() -> Environment:
	return null if _environment == null else _environment.environment


## Réapplique le profil de qualité courant.
func apply(quality: RenderQuality) -> void:
	var env := environment()
	if env == null:
		return
	env.glow_enabled = bool(quality.option("glow"))
	env.volumetric_fog_enabled = bool(quality.option("volumetric_fog"))
	env.ssao_enabled = bool(quality.option("ssao"))
	if _key_light != null:
		_key_light.shadow_enabled = bool(quality.option("shadows"))


## Allège quand l'écran se scinde — `full` faux coupe ce qui coûte le plus.
func relieve(quality: RenderQuality, full: bool) -> void:
	var env := environment()
	if env == null:
		return
	env.glow_enabled = bool(quality.option("glow")) and full
	env.volumetric_fog_enabled = bool(quality.option("volumetric_fog")) and full
	env.ssao_enabled = bool(quality.option("ssao")) and full
	if _key_light != null:
		_key_light.shadow_enabled = bool(quality.option("shadows")) and full
