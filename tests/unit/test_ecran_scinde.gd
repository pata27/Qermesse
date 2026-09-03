## Écran scindé — `docs/04` §3, `scenes/race3d/split_screen.gd`.
##
## La scission en volets est une des fonctions annoncées du logiciel : « l'écran
## se scinde en autant de volets que de paquets, jusqu'à quatre ». Elle n'avait
## AUCUN test. Elle a pourtant tout ce qui se casse en silence — une hystérésis
## asymétrique, un plafond, et une renumérotation des cassures dès qu'un coureur
## franchit la ligne — et rien de tout cela ne se voit sur une capture.
##
## Découvert par la garde des fonctions mortes : `RaceScene.split_screen()` ne
## comptait qu'un « appelant », le chemin `"…/split_screen.gd"` écrit en dur
## dans une liste de fichiers d'un autre test. La garde avait raison depuis le
## début, une chaîne de caractères la faisait taire.
##
## Ici on ne regarde pas l'image : on donne des écarts en mètres et on lit les
## cassures retenues. C'est la DÉCISION de scinder qui est éprouvée, pas son
## rendu.
extends GutTest

const SPLIT := preload("res://scenes/race3d/split_screen.gd")

var _split: SplitScreen = null


func before_each() -> void:
	_split = SPLIT.new()
	add_child_autofree(_split)
	_split.setup(World3D.new(), Vector2i(1920, 1080))


## Nombre de cassures ouvertes.
func _open_cuts() -> int:
	var count := 0
	for cut: bool in _split.cuts():
		if cut:
			count += 1
	return count


func test_un_peloton_groupe_reste_en_plein_cadre() -> void:
	_split.consider(PackedFloat32Array([1.0, 2.0, 0.5]))
	assert_eq(_open_cuts(), 0, "aucune cassure sous le seuil")
	assert_eq(_split.group_count(), 1, "un seul groupe, donc plein cadre")


func test_l_hysteresis_ouvre_haut_et_ferme_bas() -> void:
	# Sous le seuil haut : rien.
	_split.consider(PackedFloat32Array([5.0]))
	assert_eq(_open_cuts(), 0, "cinq mètres n'ouvrent pas")
	# Au-dessus : la cassure naît.
	_split.consider(PackedFloat32Array([7.0]))
	assert_eq(_open_cuts(), 1, "sept mètres ouvrent")
	assert_eq(_split.group_count(), 2, "deux volets")
	# Retour à cinq mètres : ELLE RESTE OUVERTE. C'est tout l'intérêt du seuil
	# bas — sans lui, un écart qui oscille autour de six ferait clignoter la
	# séparation à chaque image.
	_split.consider(PackedFloat32Array([5.0]))
	assert_eq(_open_cuts(), 1, "cinq mètres ne referment pas ce qui est ouvert")
	# Sous le seuil bas : elle se referme.
	_split.consider(PackedFloat32Array([3.0]))
	assert_eq(_open_cuts(), 0, "trois mètres referment")
	assert_eq(_split.group_count(), 1, "retour au plein cadre")


func test_le_nombre_de_volets_est_plafonne_a_quatre() -> void:
	# Quatre coureurs égrenés : trois cassures, donc quatre groupes. Le plafond
	# vaut aussi pour un peloton imaginaire plus large — la piste n'en a que
	# quatre, mais rien n'empêche l'appelant de passer plus d'écarts.
	_split.consider(PackedFloat32Array([20.0, 20.0, 20.0, 20.0, 20.0]))
	assert_eq(_split.group_count(), 4, "jamais plus de quatre volets")


func test_une_arrivee_renumerote_les_cassures_et_les_rejuge_au_seuil_haut() -> void:
	# Deux cassures ouvertes.
	_split.consider(PackedFloat32Array([10.0, 10.0]))
	assert_eq(_open_cuts(), 2, "deux cassures ouvertes")
	# Un coureur franchit : il sort du champ de course, il ne reste qu'un
	# écart. La cassure d'indice 0 ne désigne PLUS la même chose ; la juger au
	# seuil bas laisserait la scission ouverte sur un peloton regroupé.
	_split.consider(PackedFloat32Array([5.0]))
	assert_eq(_open_cuts(), 0, "l'écart restant est rejugé au seuil haut")


func test_une_nouvelle_course_part_en_plein_cadre() -> void:
	_split.consider(PackedFloat32Array([30.0, 30.0]))
	assert_eq(_split.group_count(), 3, "la course précédente était scindée")
	# Course abandonnée en plein écran scindé : la suivante doit repartir
	# entière, sur un peloton encore groupé sur la ligne de départ.
	_split.prime(4)
	assert_eq(_split.cuts(), [] as Array[bool], "les cassures sont oubliées")
	assert_eq(_split.group_count(), 1, "la nouvelle course part en plein cadre")
