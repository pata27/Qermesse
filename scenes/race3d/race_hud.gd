## Habillage de la fenêtre spectacle — docs/04 §5.
##
## Répond à la question que la scène seule laissait sans réponse : *quelle
## distance à faire, et où en est-on ?* Sans cet habillage, une course est
## jolie et illisible.
##
## **Lisibilité à trois mètres** (`docs/03` §6) : police d'au moins 32 px à
## 1080p, contraste élevé, et jamais d'information portée par la seule couleur —
## chaque rider porte son numéro de piste ET son nom à côté de sa teinte.
class_name RaceHud
extends CanvasLayer

## Écart minimal, en km/h, pour que le chiffre de vitesse soit RÉÉCRIT. Deux
## dixièmes : en dessous, on n'affiche plus une mesure mais son bruit.
const SPEED_STEP_KPH := 0.2
const BAND_HEIGHT := 132
## Bannière en écran scindé : les titres pleine taille mangeaient le haut de
## chaque volet, déjà étroit. Bande, chrono et titres réduits d'un peu moins
## de moitié — comme les cartes.
const BAND_HEIGHT_COMPACT := 72
const CARD_HEIGHT := 96
## Abscisses du nom et du compteur de vitesse dans une carte : leur écart est
## le budget du nom, et c'est lui qui fixe `Roster.MAX_DISPLAY_NAME`. Nommés
## pour que le test qui vérifie ce budget cesse d'être vrai si on les déplace.
const CARD_NAME_X := 26.0
const CARD_SPEED_X := 440.0
const CARD_NAME_FONT := 34
## Largeur des cartes. Élargies pour que la cadence tienne à droite sans
## chevaucher la distance, dont la longueur varie avec le mode.
const CARD_WIDTH := 700.0
## Échelle des cartes quand l'écran est scindé, voir `_layout_cards`.
const CARD_COMPACT_SCALE := 0.55
## Marge a gauche du volet — la meme en plein cadre, ou le volet est l'ecran.
const CARD_MARGIN_X := 36.0
## Plancher de l'echelle des cartes. En dessous, le nom et la vitesse ne se
## lisent plus a dix metres d'un videoprojecteur : mieux vaut mordre d'un
## cheveu sur la lame que d'afficher un chiffre illisible.
const CARD_MIN_SCALE := 0.42
const ALERT := Color("#FF3B30")
const INK := Color("#F2F5FA")
## Vert de départ, pour le « PARTEZ ! ». Le décompte doit changer de COULEUR au
## zéro : un chiffre qui devient un mot se lit trop tard quand on est penché sur
## son guidon.
const GO := Color("#2BE08A")
## Gris de second plan, pour les en-têtes et les mentions secondaires.
const MUTED := Color("#8A94A6")
## Colonnes du podium : place, coureur, temps, moyenne, pointe.
## Délai avant l'apparition du podium, le temps que la célébration se joue.
const PODIUM_DELAY_S := 5.0
## Milieu de l'espace libre à droite des cartes, en 1080p : là où vont la
## bannière et tout ce qui se centre quand les cartes occupent la gauche.
const CLEAR_CENTRE_X := (36.0 + CARD_WIDTH + 1920.0) * 0.5
## Milieu de l'écran, pour les modes sans cartes.
const SCREEN_CENTRE_X := 960.0

## Bandeau d'alerte : boite normale, boite « pleine largeur », et les tailles
## de police visees. La police RETRECIT si le texte ne rentre pas — voir
## `_place_notice`. Sans cela « COURSE INTERROMPUE — lien perdu au-delà du
## délai de grâce » mesure 1323 px pour une boite de 840 et sortait de l'ecran.
const NOTICE_WIDTH := 840.0
const NOTICE_BIG_WIDTH := 1848.0
const NOTICE_BIG_HEIGHT := 240.0
const NOTICE_FONT := 44
const NOTICE_BIG_FONT := 96
const NOTICE_MIN_FONT := 28
## Barre de tension : largeur totale, du −G au +G.
## Raideur du lissage des barres, en 1/s. Dix : elles suivent un écart qui se
## creuse sans traîner, mais ne rendent plus le pas des ticks.
const LINK_LOST_TEXT := "LIEN PERDU"
## Le chiffre d'écart ne bouge que si l'écart lissé s'en éloigne d'autant. Un
## tick vaut ~0,3 m et arrive tantôt pour l'un, tantôt pour l'autre : brut, le
## chiffre battait entre deux valeurs à chaque trame — un stroboscope.

var _controller: AppController
var _mode_label: Label
var _objective_label: Label
var _clock_label: Label
## Bloc du mode poursuite — écart, barre de tension, jauge de décision.
var _tension: RaceTension
var _cards: Dictionary = {}  # lane -> Dictionary de contrôles
var _target_speed: Dictionary = {}  # lane -> km/h visés
var _shown_speed: Dictionary = {}  # lane -> km/h lissés
var _printed_speed: Dictionary = {}  # lane -> km/h effectivement écrits
var _overlay: CanvasLayer
var _countdown_veil: ColorRect
var _countdown_holder: Control
var _countdown_label: Label
var _countdown_pulse := 0.0
var _countdown_hold_s := 0.0
var _compact := false
## Volet de chaque piste et bords gauches des volets EN PIXELS — poses par la
## scene a chaque image tant que les lames bougent. En pixels et non en
## fractions : la scene connait deja la taille de sa fenetre, et une geometrie
## qui depend d'un viewport n'est pas verifiable sans ecran.
var _pane_of: Dictionary = {}
var _pane_edges := PackedFloat32Array([0.0])
## Vrai des le depart donne, et jusqu'a la course suivante : l'ecart de
## poursuite et sa barre n'ont de sens qu'une fois que ca roule.
var _under_way := false
var _podium: RacePodium
var _podium_delay_s := 0.0
var _pending_result: RaceResult = null
var _notice: Label
var _band: ColorRect
## Ce que le bandeau « lien perdu » a recouvert, à rendre au retour du lien.
var _covered_notice := ""
## Bandeau plein ecran : l'abandon, et lui seul. Voir `_on_aborted`.
var _notice_big := false
var _abort_veil: ColorRect


## LA CONFIGURATION DE LA COURSE EN COURS, pas celle qu'on prepare.
##
## L'habillage lisait `current_config()` — les reglages VIVANTS du panneau
## operateur — a cinq endroits. Or l'operateur prepare la manche suivante
## pendant que celle-ci court : il change le mode, la distance. Le bandeau
## d'alerte, qui se place d'apres le mode, atterrissait alors AU MILIEU DES
## CARTES d'une course en distance des que le panneau etait passe sur
## poursuite — mesure : centre en x=1328 avant, x=960 apres, la course n'ayant
## pas change.
##
## Une course armee porte sa propre configuration, figee a l'armement
## (`RaceState.config`). C'est elle que l'ecran public raconte. Les reglages
## vivants ne servent qu'au repos, quand il n'y a rien d'autre a montrer.
func _race_config() -> RaceConfig:
	var state := _controller.engine.race_state()
	if state != null and state.config != null and _controller.race_in_progress():
		return state.config
	return _controller.current_config()


func setup(controller: AppController) -> void:
	_controller = controller
	layer = 2
	_build()
	_controller.progress_updated.connect(_on_progress)
	_controller.countdown_tick.connect(_on_countdown)
	_controller.race_state_changed.connect(_on_state)
	_controller.race_finished.connect(_on_finished)
	_controller.rider_eliminated.connect(_on_eliminated)
	# Les alertes — docs/04 : le rouge est réservé au faux départ, à la perte
	# de lien et au seuil de poursuite. Le public doit savoir pourquoi la
	# course se fige ou s'arrête ; un écran qui se tait passe pour planté.
	_controller.false_start_detected.connect(_on_false_start)
	_controller.link_state_changed.connect(_on_link_state)
	_controller.race_aborted.connect(_on_aborted)
	rebuild_cards()


func _build() -> void:
	_band = ColorRect.new()
	_band.color = Color(0.043, 0.055, 0.078, 0.82)
	_band.set_anchors_preset(Control.PRESET_TOP_WIDE)
	# HAUTEUR PAR LA MARGE, pas par `size`. Avec des ancres opposees inegales
	# — 0 a gauche, 1 a droite — Godot recalcule la taille apres `_ready` et
	# ecrase celle qu'on vient de poser, en le disant dans un avertissement.
	_band.offset_bottom = BAND_HEIGHT
	_band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_band)

	_mode_label = make_label(28, INK)
	_mode_label.position = Vector2(36, 18)
	add_child(_mode_label)

	_objective_label = make_label(40, INK)
	_objective_label.position = Vector2(36, 56)
	add_child(_objective_label)

	# Chrono en chiffres géants — docs/04 §5.
	_clock_label = make_label(84, INK)
	_clock_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_clock_label.position.y = 14
	add_child(_clock_label)

	# CONFIGURÉ AVANT D'ENTRER DANS L'ARBRE, comme le podium : un `Control`
	# ajouté avant d'être dimensionné se retrouve de taille nulle, et tout son
	# contenu s'empile en haut à gauche. La leçon a déjà coûté une régression.
	_tension = RaceTension.new()
	_tension.name = "Tension"
	_tension.build(SCREEN_CENTRE_X)
	add_child(_tension)

	# LES PLEIN-ÉCRANS ONT LEUR PROPRE COUCHE.
	#
	# L'ordre de dessin d'un `CanvasLayer` suit l'ordre des enfants, et les
	# cartes des coureurs sont créées PLUS TARD, par `rebuild_cards`, à chaque
	# armement. Le décompte et le podium, construits ici, se retrouvaient donc
	# DESSOUS : le voile assombrissait la scène mais les barres de progression
	# et les cartes lui passaient par-dessus. Une couche supérieure règle la
	# question une fois pour toutes, quel que soit l'ordre de construction.
	_overlay = CanvasLayer.new()
	_overlay.name = "PleinEcran"
	_overlay.layer = layer + 1
	add_child(_overlay)

	_build_countdown()
	# CONFIGURE PUIS AJOUTE, dans cet ordre. L'inverse laissait le voile a une
	# taille nulle : tout le classement se tassait en haut a gauche, sur une
	# scene non assombrie. Vu a la capture, pas au test — un podium mal place
	# reste un podium qui contient les bons chiffres.
	_podium = RacePodium.new()
	_podium.setup(_controller)
	_overlay.add_child(_podium)

	# Même place que le bloc poursuite, pour la même raison : centrée sur
	# l'écran, la bannière passait sur la première carte.
	# VOILE D'ABANDON. Le bandeau plein ecran passait au travers des cartes des
	# coureurs — a quatre pistes elles descendent jusqu'au milieu de l'ecran.
	# Le mettre simplement au-dessus laissait une collision : du rouge sur une
	# carte, illisible des deux cotes. Assombrir la scene est le langage deja
	# employe par le decompte et le podium, et il dit la meme chose ici — ce
	# qui se passait n'a plus cours, c'est ce texte qui compte.
	_abort_veil = ColorRect.new()
	_abort_veil.name = "AbortVeil"
	_abort_veil.color = Color(0.02, 0.03, 0.05, 0.72)
	_abort_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	_abort_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_abort_veil.visible = false
	_overlay.add_child(_abort_veil)

	_notice = make_label(NOTICE_FONT, ALERT)
	_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_notice)
	_place_notice()


## Une carte par piste active. Reconstruites à chaque armement : le nombre de
## pistes peut changer d'une course à l'autre.
func rebuild_cards() -> void:
	for entry: Dictionary in _cards.values():
		(entry["root"] as Node).queue_free()
	_cards.clear()

	# PAS DE CARTES EN POURSUITE. Elles formaient un bloc qui cachait la scène,
	# pour redire ce que la barre de tension montre déjà par ses couleurs :
	# qui mène, et de combien chacun est en retard. Le sujet du mode est
	# l'écart, il occupe le centre de l'écran, seul (docs/04 §5).
	if _race_config().mode == RaceConfig.Mode.PURSUIT:
		return

	var lanes := _controller.roster.active_lanes()
	for index: int in range(lanes.size()):
		var lane: int = lanes[index]
		var rider := _controller.roster.rider(lane)
		var color := Color(rider.color)

		var root := Control.new()
		root.size = Vector2(CARD_WIDTH, CARD_HEIGHT)
		root.set_meta("index", index)
		root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(root)

		var backdrop := ColorRect.new()
		backdrop.color = Color(0.043, 0.055, 0.078, 0.66)
		backdrop.size = Vector2(CARD_WIDTH, CARD_HEIGHT)
		root.add_child(backdrop)

		# Pastille de couleur ET numéro de piste : jamais la couleur seule.
		var chip := ColorRect.new()
		chip.color = color
		chip.position = Vector2(0, 0)
		chip.size = Vector2(10, CARD_HEIGHT)
		root.add_child(chip)

		var name_label := make_label(CARD_NAME_FONT, color)
		name_label.text = "P%d  %s" % [lane + 1, rider.display_name()]
		name_label.position = Vector2(CARD_NAME_X, 6)
		# BORNÉ EN PIXELS, pas en caractères. Dix-huit caractères larges font
		# 623 px là où la carte en offre 414 : compter les lettres ne garantit
		# rien. La coupure se fait donc à la largeur réelle, avec des points de
		# suspension. La borne en caractères, elle, sert aux colonnes de texte
		# du panneau opérateur, où un caractère vaut une colonne.
		name_label.size.x = CARD_SPEED_X - CARD_NAME_X
		name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		root.add_child(name_label)

		var speed_label := make_label(40, INK)
		speed_label.position = Vector2(CARD_SPEED_X, 2)
		root.add_child(speed_label)

		# Cadence — docs/04 §5. Déduite du développement déclaré par
		# l'opérateur, puisque le capteur ne mesure que le rouleau.
		var cadence_label := make_label(28, MUTED)
		cadence_label.position = Vector2(CARD_WIDTH - 176.0, 52)
		cadence_label.size.x = 160
		cadence_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		root.add_child(cadence_label)

		var distance_label := make_label(28, INK)
		distance_label.position = Vector2(26, 50)
		root.add_child(distance_label)

		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.position = Vector2(26, 84)
		bar.size = Vector2(510, 8)
		var style := StyleBoxFlat.new()
		style.bg_color = color
		bar.add_theme_stylebox_override("fill", style)
		root.add_child(bar)

		_cards[lane] = {
			"root": root,
			"speed": speed_label,
			"cadence": cadence_label,
			"distance": distance_label,
			"bar": bar,
			"name": name_label,
		}
	_refresh_objective()
	_reset_cards_to_start()


## Remet les cartes a leur etat de depart : zero, et l'objectif annonce.
##
## Elles n'etaient remplies qu'a la premiere trame `R:`. Pendant les trois
## secondes du decompte — le moment ou tout le monde regarde — elles montraient
## un nom et deux lignes VIDES, ce qui se lit comme un affichage casse. Une
## carte doit dire ce qu'elle contiendra avant de le contenir.
func _reset_cards_to_start() -> void:
	var config := _race_config()
	var development: float = maxf(_controller.settings.development_m, 0.5)
	for lane: Variant in _cards.keys():
		var card: Dictionary = _cards[lane]
		(card["speed"] as Label).text = "%5.1f km/h" % 0.0
		(card["cadence"] as Label).text = "%.0f tr/min" % (0.0 / development)
		(card["bar"] as ProgressBar).value = 0.0
		match config.mode:
			RaceConfig.Mode.TIME:
				(card["distance"] as Label).text = (
					"%.0f m parcourus   —   reste %.1f s" % [0.0, config.duration_s]
				)
			_:
				(card["distance"] as Label).text = (
					"%.0f m parcourus   —   reste %.0f m" % [0.0, config.distance_m]
				)
	# Le chiffre affiche repart de zero lui aussi : sans cela, l'hysteresis
	# comparerait la premiere vitesse de la course a celle de la precedente.
	_printed_speed.clear()


## Anime le décompte : le chiffre entre agrandi puis se resserre, et l'annonce
## de départ s'efface d'elle-même.
	# Positions et échelle selon le mode courant, dès la construction : sans
	# cet appel les cartes restaient à l'origine jusqu'à la première scission.
	_layout_cards()


## Fait apparaître le podium une fois la célébration jouée.
func _tick_podium(delta: float) -> void:
	if _pending_result == null:
		return
	_podium_delay_s -= delta
	if _podium_delay_s <= 0.0:
		_show_podium(_pending_result)
		_pending_result = null


func _animate_countdown(delta: float) -> void:
	if _countdown_veil == null or not _countdown_veil.visible:
		return
	_countdown_pulse = maxf(0.0, _countdown_pulse - delta * 3.2)
	var eased := _countdown_pulse * _countdown_pulse
	var scale := 1.0 + eased * 0.55
	_countdown_holder.pivot_offset = _countdown_holder.size * 0.5
	_countdown_holder.scale = Vector2(scale, scale)
	_countdown_veil.color.a = 0.72 - eased * 0.18

	if _countdown_hold_s > 0.0:
		_countdown_hold_s -= delta
		if _countdown_hold_s <= 0.0:
			_countdown_veil.visible = false


## Rapproche les chiffres affichés de leur cible. Séparé de `_on_progress` :
## celui-ci arrive au rythme du boîtier, pas à celui de l'écran, et un lissage
## piloté par un signal externe ne serait pas régulier.
func _process(delta: float) -> void:
	_animate_countdown(delta)
	_tick_podium(delta)
	_tension.advance(delta)
	if _target_speed.is_empty():
		return
	var alpha := 1.0 - exp(-delta * 4.0)
	for lane: int in _cards:
		if not _target_speed.has(lane):
			continue
		var shown: float = _shown_speed.get(lane, float(_target_speed[lane]))
		shown = lerpf(shown, float(_target_speed[lane]), alpha)
		_shown_speed[lane] = shown

		# HYSTÉRÉSIS SUR LE CHIFFRE, et pas seulement lissage de la valeur.
		#
		# Lisser ne suffit pas : la valeur lissée converge vers sa cible, et si
		# celle-ci oscille de un ou deux dixièmes, le dernier chiffre bascule à
		# chaque image. C'est ce battement qui se lit comme un scintillement,
		# quelle que soit la constante de temps.
		#
		# Le chiffre affiché ne bouge donc que si la valeur lissée s'en écarte
		# d'au moins `SPEED_STEP_KPH`. Il reste alors immobile à allure stable,
		# et suit franchement une accélération réelle.
		var printed: float = _printed_speed.get(lane, INF)
		if absf(shown - printed) < SPEED_STEP_KPH:
			continue
		_printed_speed[lane] = shown
		var card: Dictionary = _cards[lane]
		(card["speed"] as Label).text = "%5.1f km/h" % shown
		var development: float = maxf(_controller.settings.development_m, 0.5)
		(card["cadence"] as Label).text = "%.0f tr/min" % (shown / 3.6 / development * 60.0)


## DÉCOMPTE PLEIN ÉCRAN — docs/04 §5.
##
## Synchronisé sur les trames `CD:` du firmware, JAMAIS sur une horloge PC : les
## LED physiques du boîtier et l'écran doivent annoncer la même chose. Un
## décompte qui avance d'une demi-seconde sur les LED est pire que pas de
## décompte du tout, parce qu'il fait partir les coureurs au mauvais moment.
##
## Il occupe tout l'écran parce que c'est le seul moment où l'on ne regarde rien
## d'autre.
func _build_countdown() -> void:
	_countdown_veil = ColorRect.new()
	_countdown_veil.name = "CountdownVeil"
	_countdown_veil.color = Color(0.02, 0.03, 0.05, 0.72)
	_countdown_veil.set_anchors_preset(Control.PRESET_FULL_RECT)
	_countdown_veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_countdown_veil.visible = false
	_overlay.add_child(_countdown_veil)

	# Le chiffre vit dans un conteneur centré : c'est lui qu'on met à l'échelle,
	# sinon l'agrandissement se ferait depuis le coin haut-gauche du libellé.
	_countdown_holder = Control.new()
	_countdown_holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	_countdown_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_countdown_veil.add_child(_countdown_holder)

	_countdown_label = make_label(300, INK)
	_countdown_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_countdown_holder.add_child(_countdown_label)


## Place les cartes selon le mode, plein cadre ou compact.
##
## COMPACTES DÈS QUE L'ÉCRAN SE SCINDE. En plein cadre, la colonne de cartes
## occupe 736 px sur la gauche et ne gêne personne. Scindé en trois ou quatre,
## le volet du LEADER fait 480 px et tient tout entier sous cette colonne :
## le portique, la piste devant lui, parfois lui-même disparaissaient sous
## l'habillage. Réduites d'un peu plus de moitié, les cartes gardent toutes
## leurs informations et s'arrêtent avant la hauteur où roulent les coureurs.
func _layout_cards() -> void:
	# Rang de chaque carte DANS SON VOLET : deux coureurs d'un meme paquet
	# s'empilent, et le volet voisin recommence en haut.
	var filled: Dictionary = {}
	for lane: int in _ordered_lanes():
		var root := (_cards[lane] as Dictionary)["root"] as Control
		var pane := int(_pane_of.get(lane, 0))
		var row := int(filled.get(pane, 0))
		filled[pane] = row + 1
		var scale := _pane_scale(pane)
		root.scale = Vector2(scale, scale)
		var left := 0.0
		if pane < _pane_edges.size():
			left = maxf(_pane_edges[pane], 0.0)
		var step := (CARD_HEIGHT + 12.0) * scale
		root.position = Vector2(left + _pane_margin(pane), band_height() + 28 + row * step)


## Marge a gauche de la carte dans son volet. Plus etroite des le second volet :
## la lame lumineuse y fait deja la separation, et chaque pixel compte.
func _pane_margin(pane: int) -> float:
	return CARD_MARGIN_X if pane == 0 else CARD_MARGIN_X * 0.4


## Echelle des cartes d'un volet.
##
## LA CARTE TIENT DANS SON VOLET, ou elle n'y est pas.
##
## Quatre volets font 480 px chacun, mais la lame est INCLINEE : en haut de
## l'image, la ou vivent les cartes, elle est decalee d'une centaine de pixels
## vers la droite. Le dernier volet n'y mesure plus que 344 px, et une carte
## compacte de 385 px sortait de l'ecran — le compteur de vitesse du dernier
## coureur etait coupe par le bord. La carte se met donc a la largeur de son
## volet quand celui-ci est trop etroit, sans jamais depasser l'echelle
## compacte : un volet large ne grossit pas ses cartes.
func _pane_scale(pane: int) -> float:
	var base := CARD_COMPACT_SCALE if _compact else 1.0
	if not _compact or pane + 1 >= _pane_edges.size():
		return base
	var room := _pane_edges[pane + 1] - _pane_edges[pane] - _pane_margin(pane) * 2.0
	if room <= 0.0:
		return base
	return clampf(minf(base, room / CARD_WIDTH), CARD_MIN_SCALE, base)


## Pistes dans l'ordre ou leurs cartes ont ete construites. L'ordre compte : il
## fixe qui est en haut de son volet.
func _ordered_lanes() -> Array[int]:
	var lanes: Array[int] = []
	for lane: Variant in _cards.keys():
		lanes.append(int(lane))
	lanes.sort_custom(func(a: int, b: int) -> bool:
		var ia := int(((_cards[a] as Dictionary)["root"] as Control).get_meta("index", 0))
		var ib := int(((_cards[b] as Dictionary)["root"] as Control).get_meta("index", 0))
		if ia != ib:
			return ia < ib
		return a < b)
	return lanes


## Volet de chaque piste et bords des volets — docs/04 §5.
##
## LES CARTES SUIVENT LES LAMES. Empilees en haut a gauche, elles decrivaient
## quatre coureurs dont un seul etait visible sous elles : le spectateur qui
## regardait le quatrieme volet cherchait la vitesse de son coureur a l'autre
## bout de l'ecran. `edges` porte le bord GAUCHE de chaque volet, EN PIXELS, a
## la hauteur des cartes — lame en cours d'entree comprise —, PUIS le bord droit
## du dernier volet. Il en faut donc un de plus que de volets : sans lui, on ne
## saurait pas si la derniere carte tient.
func set_pane_layout(pane_of: Dictionary, edges: PackedFloat32Array) -> void:
	_pane_of = pane_of
	_pane_edges = edges
	_layout_cards()


## Echelle appliquee a la carte d'une piste — pour les tests.
func card_scale(lane: int) -> float:
	if not _cards.has(lane):
		return 0.0
	return (((_cards[lane] as Dictionary)["root"]) as Control).scale.x


## Position de la carte d'une piste — pour les tests, qui verifient qu'elle
## tombe bien dans son volet.
func card_position(lane: int) -> Vector2:
	if not _cards.has(lane):
		return Vector2.ZERO
	return (((_cards[lane] as Dictionary)["root"]) as Control).position


## Active ou non le mode compact ; appelé par la scène selon le nombre de volets.
func set_compact(compact: bool) -> void:
	if compact == _compact:
		return
	_compact = compact
	_layout_banner()
	_layout_cards()


func band_height() -> float:
	return float(BAND_HEIGHT_COMPACT if _compact else BAND_HEIGHT)


## Place le bandeau d'alerte, et REDUIT sa police jusqu'a ce que le texte tienne
## dans sa boite.
##
## La boite etait fixe — 840 px — mais pas le texte : « COURSE INTERROMPUE —
## arrêt opérateur » mesure 895 px, et le pire cas 1323. Un bandeau tronque est
## pire qu'un bandeau plus petit : il donne un mot pour un autre, devant le
## public.
##
## L'ABANDON PREND TOUT L'ECRAN, au milieu. La course est finie, plus rien
## d'autre ne compte a cet instant, et ce sont les coureurs qu'il faut
## atteindre — sur leurs rouleaux, a plusieurs metres de l'ecran.
func _place_notice() -> void:
	if _notice == null:
		return
	# AU-DESSUS DES CARTES QUAND IL PREND TOUT L'ECRAN. Les cartes des coureurs
	# sont construites a chaque armement, donc APRES la banniere, et un
	# `CanvasLayer` dessine dans l'ordre de ses enfants : a quatre pistes elles
	# descendent jusqu'au milieu de l'ecran et coupaient le bandeau d'abandon
	# en deux. La couche superieure — celle du voile et du podium — regle la
	# question quel que soit l'ordre de construction. Hors abandon il revient
	# en dessous : la, il se range dans l'espace libre a cote des cartes, et
	# passer devant le decompte n'aurait aucune raison d'etre.
	_abort_veil.visible = _notice_big
	var wanted: Node = _overlay if _notice_big else self
	if _notice.is_inside_tree() and _notice.get_parent() != wanted:
		_notice.reparent(wanted)
	var width := NOTICE_BIG_WIDTH if _notice_big else NOTICE_WIDTH
	var font := _notice.get_theme_font("font")
	var font_size := NOTICE_BIG_FONT if _notice_big else NOTICE_FONT
	while font_size > NOTICE_MIN_FONT and _notice_width(font, font_size) > width:
		font_size -= 2
	_notice.add_theme_font_size_override("font_size", font_size)
	_notice.size.x = width
	if _notice_big:
		_notice.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_notice.size.y = NOTICE_BIG_HEIGHT
		_notice.position = Vector2(
			SCREEN_CENTRE_X - width * 0.5, 540.0 - NOTICE_BIG_HEIGHT * 0.5
		)
		return
	_notice.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_notice.size.y = 0.0
	# En poursuite les cartes sont absentes : la banniere revient au milieu de
	# l'ecran. Dans les autres modes elle se centre dans l'espace qu'elles
	# laissent libre.
	var pursuit := _race_config().mode == RaceConfig.Mode.PURSUIT
	var centre := SCREEN_CENTRE_X if pursuit else CLEAR_CENTRE_X
	_notice.position = Vector2(centre - width * 0.5, band_height() + 16.0)


func _notice_width(font: Font, font_size: int) -> float:
	return font.get_string_size(_notice.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x


## La bannière suit le mode compact : titres, chrono et bande réduits.
func _layout_banner() -> void:
	var height := band_height()
	_band.offset_bottom = height
	_mode_label.add_theme_font_size_override("font_size", 18 if _compact else 28)
	_mode_label.position = Vector2(36, 8 if _compact else 18)
	_objective_label.add_theme_font_size_override("font_size", 24 if _compact else 40)
	_objective_label.position = Vector2(36, 32 if _compact else 56)
	_clock_label.add_theme_font_size_override("font_size", 48 if _compact else 84)
	_clock_label.position.y = 8 if _compact else 14
	_place_notice()


## Style commun de tout l'habillage — `RacePodium` s'en sert aussi.
static func make_label(size: int, color: Color) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	# Contour sombre : indispensable sur un vidéoprojecteur pâle, où un texte
	# clair sur fond clair de piste devient illisible.
	label.add_theme_color_override("font_outline_color", Color(0.02, 0.03, 0.05))
	label.add_theme_constant_override("outline_size", 6)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _refresh_objective() -> void:
	var config := _race_config()
	_mode_label.text = "MODE %s" % config.mode_name().to_upper()
	match config.mode:
		RaceConfig.Mode.DISTANCE:
			_objective_label.text = "%.0f m" % config.distance_m
		RaceConfig.Mode.TIME:
			_objective_label.text = "%.0f s" % config.duration_s
		RaceConfig.Mode.PURSUIT:
			_objective_label.text = "écart %.0f m" % config.gap_m
	# L'ECART N'APPARAIT QU'AU DEPART. Avant, tout le monde est sur la ligne :
	# « 0.0 m » et une barre vide ne disent rien, et viennent concurrencer le
	# chiffre du decompte — le moment le plus regarde de la soiree. En mode
	# temps, ce meme moment montre les noms des coureurs, ce qui est utile.
	var pursuit := config.mode == RaceConfig.Mode.PURSUIT
	_tension.visible = pursuit and _under_way
	# En poursuite les cartes sont absentes : la bannière revient au milieu de
	# l'écran. Dans les autres modes elle se centre dans l'espace qu'elles
	# laissent libre.
	_place_notice()


## Rejoue une transition d'etat, pour une scene montee en pleine course. Voir
## `RaceScene._catch_up_if_running` : sans cela, l'ecran public ouvert en retard
## reste ampute du sujet de son mode jusqu'a la course suivante.
func replay_state(previous: int, current: int) -> void:
	_on_state(previous, current)


func _on_state(_previous: int, current: int) -> void:
	if current == RaceEngine.State.RUNNING:
		_under_way = true
		_refresh_objective()
	if current == RaceEngine.State.ARMING:
		_under_way = false
		rebuild_cards()
		# LES LISSAGES REPARTENT DE ZÉRO. Ils survivaient aux cartes : à la
		# deuxième course, la première trame R: faisait DÉCROÎTRE l'ancienne
		# vitesse — 52, 51,8, 51,6 km/h… — sur des coureurs qui démarrent, et
		# la barre de tension repartait de son dernier état.
		_target_speed.clear()
		_shown_speed.clear()
		_printed_speed.clear()
		_tension.reset()
		# Une nouvelle course efface la précédente : bandeau et podium ne
		# doivent pas rester par-dessus le décompte suivant.
		_clear_banner_and_podium()
		_notice.visible = true
		_refresh_objective()
	elif current == RaceEngine.State.FINISHED or current == RaceEngine.State.IDLE:
		# La décision est prise : le compte à rebours n'a plus rien à dire.
		_tension.set_decision("", false)
		if current == RaceEngine.State.IDLE:
			_clock_label.text = ""


func _on_countdown(value: int) -> void:
	# Décompte synchronisé sur les trames CD:, jamais sur une horloge PC :
	# les LED physiques et l'écran doivent être d'accord (docs/04 §5).
	_clock_label.text = str(value) if value > 0 else "PARTEZ"
	_countdown_label.text = str(value) if value > 0 else "PARTEZ !"
	_countdown_label.add_theme_color_override(
		"font_color", GO if value <= 0 else INK
	)
	_countdown_veil.visible = true
	# Chaque annonce repart d'un pic : le chiffre entre gros et se resserre,
	# ce qui donne le battement du décompte.
	_countdown_pulse = 1.0
	# « PARTEZ ! » s'efface tout seul ; les chiffres restent jusqu'au suivant.
	_countdown_hold_s = 0.9 if value <= 0 else 0.0


func _on_progress(state: RaceState) -> void:
	var config := state.config
	_clock_label.text = "%.2f s" % (state.elapsed_ms / 1000.0)

	var leader := -1
	var trailer := -1
	for lane: int in _cards:
		if leader < 0 or state.distance_m[lane] > state.distance_m[leader]:
			leader = lane
		if trailer < 0 or state.distance_m[lane] < state.distance_m[trailer]:
			trailer = lane

	for lane: int in _cards:
		var card: Dictionary = _cards[lane]
		# Vitesse d'AFFICHAGE, lissée sur une seconde côté moteur, puis LISSÉE
		# ENCORE à l'écran par `_process`. La fenêtre d'une seconde supprime les
		# paliers de tick mais laisse le dixième battre entre deux valeurs
		# voisines à chaque rafraîchissement ; c'est ce battement qui se voyait.
		# Le chiffre affiché rejoint sa cible en continu, il ne s'y pose plus.
		_target_speed[lane] = state.display_speed_kph[lane]
		# La cadence est écrite avec la vitesse, dans `_process`, sous la même
		# hystérésis : écrite ici à 100 Hz depuis la vitesse « lissée », son
		# dernier chiffre battait quand même à chaque trame — un tour par
		# minute vaut 0,04 km/h, bien moins que le bruit résiduel.

		var done := state.distance_m[lane]
		match config.mode:
			RaceConfig.Mode.DISTANCE:
				# LA question de l'utilisateur : combien reste-t-il ?
				var left := maxf(0.0, config.distance_m - done)
				# UN PENALISE N'A PAS PARCOURU MOINS QUE RIEN. Son handicap est
				# NEGATIF et s'ajoute a la distance : la carte annoncait donc
				# « -10 m parcourus » au public, un nombre juste au sens du
				# calcul et faux au sens de la phrase — il n'a pas pedale
				# -10 m, il est parti dix metres derriere la ligne.
				#
				# Tant qu'il n'a pas rattrape la ligne, la carte dit ce qui se
				# passe reellement. C'est aussi ce que `docs/02` §4 demande de
				# la politique PENALITE — annoncer la piste et son handicap :
				# le bandeau le dit une fois, la carte le tient sous les yeux
				# tant que ca dure.
				(card["distance"] as Label).text = (
					"%.0f m de pénalité   —   reste %.0f m" % [-done, left]
					if done < 0.0
					else "%.0f m parcourus   —   reste %.0f m" % [done, left]
				)
				(card["bar"] as ProgressBar).value = (
					clampf(done / maxf(1.0, config.distance_m), 0.0, 1.0) * 100.0
				)
			RaceConfig.Mode.TIME:
				var remaining := maxf(0.0, config.duration_s - state.elapsed_ms / 1000.0)
				# Meme regle : un penalise affiche sa penalite, pas une distance
				# negative. En mode temps la penalite se paie en distance, et
				# c'est bien elle qui manquera au classement.
				(card["distance"] as Label).text = (
					"%.0f m de pénalité   —   reste %.1f s" % [-done, remaining]
					if done < 0.0
					else "%.0f m parcourus   —   reste %.1f s" % [done, remaining]
				)
				(card["bar"] as ProgressBar).value = (
					clampf(state.elapsed_ms / 1000.0 / maxf(1.0, config.duration_s), 0.0, 1.0)
					* 100.0
				)
			RaceConfig.Mode.PURSUIT:
				var behind := state.distance_m[leader] - done
				# Meme regle qu'en distance : un penalise affiche sa penalite,
				# pas une distance negative.
				(card["distance"] as Label).text = (
					"%.0f m de pénalité   —   %s" % [-done, "à %.1f m" % behind]
					if done < 0.0
					else "%.0f m parcourus   —   %s"
					% [done, "en tête" if lane == leader else "à %.1f m" % behind]
				)
				(card["bar"] as ProgressBar).value = (
					clampf(1.0 - behind / maxf(1.0, config.gap_m), 0.0, 1.0) * 100.0
				)

		if state.eliminated[lane]:
			(card["name"] as Label).modulate = Color(0.55, 0.55, 0.55)

	if config.mode == RaceConfig.Mode.PURSUIT:
		# Seuls ceux qui courent encore comptent. Un éliminé a sa distance
		# FIGÉE : le garder dans le calcul faisait croître l'écart affiché
		# indéfiniment après son élimination.
		var racing: Array[int] = []
		for lane: int in state.config.active_riders:
			if not state.eliminated[lane]:
				racing.append(lane)
		racing = state.by_distance(racing)
		if racing.size() >= 2:
			var head: int = racing[0]
			var last: int = racing[racing.size() - 1]
			var scale := maxf(1.0, config.gap_m)
			_tension.set_gap(state.distance_m[head] - state.distance_m[last], scale)
			var lead_ratio := (state.distance_m[head] - state.distance_m[racing[1]]) / scale
			var chasers: Array = []
			for index: int in range(1, racing.size()):
				var lane: int = racing[index]
				chasers.append([
					(state.distance_m[head] - state.distance_m[lane]) / scale,
					Color(_controller.roster.rider(lane).color),
				])
			_tension.set_bars(lead_ratio, Color(_controller.roster.rider(head).color), chasers)
		_tension.set_bounds("−%.0f m" % config.gap_m, "+%.0f m" % config.gap_m)
		# Rouge sur la dernière demi-minute : le public doit sentir que ça va
		# tomber. (Pas dans la bannière : en 1280 px l'objectif allongé
		# passait sous le chrono.)
		_tension.set_decision(
			RulePursuit.decision_text(state),
			RulePursuit.seconds_before_decision(state) < 30.0
		)


func _on_eliminated(rider: int, rank: int, _gap_m: float) -> void:
	_notice.text = "PISTE %d ÉLIMINÉE — rang %d" % [rider + 1, rank]
	_covered_notice = ""
	_notice_big = false
	_place_notice()


## docs/02 §4 : « bandeau + son ». Quelle que soit la politique — sous
## RELANCE, l'abandon qui suit reprendra la parole.
func _on_false_start(rider: int, policy: int) -> void:
	# LA POLITIQUE CHOISIE EST RESPECTÉE À L'ÉCRAN, pas seulement dans le
	# moteur. `IGNORE` est « loggué UNIQUEMENT » : la ligne FALSE_START part au
	# CSV, l'écran public ne dit rien. Un bandeau rouge malgré la politique
	# choisie, c'est la politique ignorée.
	if policy == RaceConfig.FalseStartPolicy.IGNORE:
		return
	_notice.add_theme_color_override("font_color", ALERT)
	if policy == RaceConfig.FalseStartPolicy.PENALTY:
		# Sans un mot, le public voit un coureur inexplicablement distancé dès
		# le départ — et croit à un bug plutôt qu'à une sanction.
		# LE CHIFFRE EST CELUI QUE LE MOTEUR APPLIQUE : la pénalité de la course
		# armée, pas le réglage vivant du panneau. L'écran annonçait 25 m quand
		# l'opérateur préparait la manche suivante et que le moteur en
		# appliquait 10 — mesuré.
		_notice.text = (
			"PISTE %d PÉNALISÉE — DÉPART %.0f m EN ARRIÈRE"
			% [rider + 1, _race_config().false_start_penalty_m]
		)
	else:
		_notice.text = "FAUX DÉPART — PISTE %d" % (rider + 1)
	_covered_notice = ""
	_notice_big = false
	_place_notice()


## docs/01 §6.2 : la course se fige sur la dernière valeur connue, le bandeau
## le dit. Au retour du lien, il rend ce qu'il avait recouvert — une
## élimination survenue juste avant ne doit pas disparaître avec l'alerte.
func _on_link_state(state: int) -> void:
	if state == Protocol.State.LINK_LOST:
		if _notice.text != LINK_LOST_TEXT:
			_covered_notice = _notice.text
		_notice.add_theme_color_override("font_color", ALERT)
		_notice.text = LINK_LOST_TEXT
		# Le lien perdu NE PREND PAS tout l'ecran : la course continue, figee
		# sur sa derniere valeur, et le bandeau ne doit pas masquer ce qu'elle
		# montre. Seul l'abandon a droit au plein ecran.
		_notice_big = false
		_place_notice()
	elif _notice.text == LINK_LOST_TEXT:
		_notice.text = _covered_notice
		_covered_notice = ""
		_place_notice()


func _clear_banner_and_podium() -> void:
	_notice.text = ""
	_covered_notice = ""
	_notice_big = false
	_notice.add_theme_color_override("font_color", ALERT)
	_abort_veil.visible = false
	_podium.visible = false
	_pending_result = null
	_place_notice()


func _on_aborted(note: String) -> void:
	# L'ARRET DE LA VITRINE N'EST PAS UN INCIDENT : le bandeau d'abandon est
	# reserve aux vrais abandons. La manche de demonstration n'a pas eu lieu,
	# l'ecran revient au repos ; l'armement suivant reconstruit le reste.
	if _controller.demo_mode:
		_clear_banner_and_podium()
		_tension.visible = false
		for entry: Dictionary in _cards.values():
			(entry["root"] as Control).visible = false
		return
	# LE MOTIF EST AFFICHÉ. Le moteur le connaît — faux départ, plafond, lien
	# perdu — et il était jeté : le public voyait une course s'arrêter sans
	# raison, et l'opérateur devait l'expliquer au micro.
	_notice.add_theme_color_override("font_color", ALERT)
	_notice.text = "COURSE INTERROMPUE" if note.is_empty() else "COURSE INTERROMPUE — %s" % note
	_covered_notice = ""
	_notice_big = true
	# LES CARTES S'EFFACENT, comme au podium. Le voile seul les laissait sous
	# le texte : a quatre pistes la derniere passe exactement dessous, et deux
	# messages superposes n'en font aucun. Ce qu'elles montrent — vitesse
	# instantanee, distance restante — n'a plus cours, la course est finie ;
	# le classement partiel, lui, est au panneau Resultats. L'armement suivant
	# les reconstruit.
	_tension.visible = false
	for entry: Dictionary in _cards.values():
		(entry["root"] as Control).visible = false
	_place_notice()


## LE PODIUM A L'ÉCRAN POUR LUI SEUL. Le voile ne fait qu'assombrir ce qui est
## dessous ; en poursuite, l'écart géant en rouge et la barre de tension
## restaient lisibles à travers et venaient s'écraser sur le titre. Tout ce qui
## parle de la course EN COURS s'efface — l'armement suivant le remet. Ces
## widgets appartiennent au HUD, la décision reste donc ici ; la mise en page
## du classement, elle, est partie dans `RacePodium`.
func _show_podium(result: RaceResult) -> void:
	_tension.visible = false
	_notice.visible = false
	for entry: Dictionary in _cards.values():
		(entry["root"] as Control).visible = false
	_podium.show_result(result, _objective_label.text)


func podium_text() -> String:
	return _podium.text()


func card_name_label(lane: int) -> Label:
	return null if not _cards.has(lane) else (_cards[lane] as Dictionary)["name"] as Label


## La ligne de detail d'une carte — distance parcourue et ce qu'il reste.
func card_detail_text(lane: int) -> String:
	if not _cards.has(lane):
		return ""
	return ((_cards[lane] as Dictionary)["distance"] as Label).text


func card_speed_text(lane: int) -> String:
	return "" if not _cards.has(lane) else ((_cards[lane] as Dictionary)["speed"] as Label).text


func gap_visible() -> bool:
	return _tension.visible


func decision_text() -> String:
	return _tension.decision_text()


## Le bandeau du haut — mode et objectif — pour les tests, qui verifient qu'il
## dit la course EN COURS et non les reglages qu'on prepare pour la suivante.
func notice_text() -> String:
	return _notice.text


## La boite du bandeau et la largeur que son texte occupe reellement. Pour les
## tests, qui verifient qu'il TIENT : un bandeau tronque donne un mot pour un
## autre, et cela ne se lit dans aucune assertion sur le texte.
func notice_metrics() -> Dictionary:
	return {
		"rect": Rect2(_notice.position, _notice.size),
		"veil": _abort_veil.visible,
		"above_cards": _notice.get_parent() == _overlay,
		"text_width": _notice_width(
			_notice.get_theme_font("font"), _notice.get_theme_font_size("font_size")
		),
	}


func notice_color() -> Color:
	return _notice.get_theme_color("font_color")


func _on_finished(result: RaceResult) -> void:
	var winner := result.winner()
	_notice.add_theme_color_override("font_color", INK)
	_notice.text = (
		"VAINQUEUR — P%d %s%s"
		% [
			winner + 1,
			result.display_name(winner),
			"   [INTERROMPUE]" if result.was_stopped() else "",
		]
	)
	# Le podium laisse d'abord la célébration se jouer : arriver par-dessus les
	# bras levés et les confettis volerait le moment aux coureurs.
	_podium_delay_s = PODIUM_DELAY_S
	_pending_result = result
