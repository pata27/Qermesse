// Composition de l'écran scindé — une seule passe, pas de copie d'écran.
//
// La vue du LEADER est rendue directement dans la fenêtre ; celle du poursuivant
// arrive par une texture de `SubViewport`. Ce shader ne fait que décider, pixel
// par pixel, laquelle des deux montrer — et dessiner la lame lumineuse qui les
// sépare. Aucun `hint_screen_texture`, donc aucune recopie du tampon d'écran.
shader_type canvas_item;
render_mode blend_mix;

uniform sampler2D other_view : filter_linear;
// Fenêtre d'écran RÉELLEMENT rendue par cette vue, en fraction de largeur.
// Chaque volet ne rend que sa tranche : rendre l'image entière pour n'en
// montrer qu'un quart coûtait quatre fois les pixels à quatre volets, et c'est
// le remplissage qui limite cette scène, pas la géométrie.
uniform float slice_u0 = 0.0;
uniform float slice_w = 1.0;
// 0 = écran plein pour le leader, 1 = séparation complète.
uniform float split_amount = 0.0;
// Inclinaison de la lame, en fraction de largeur d'écran.
uniform float slant = 0.16;
// Place de repos de la lame, en fraction de largeur. Avec plusieurs volets,
// chacun a la sienne : deux lames se posent au tiers et aux deux tiers.
uniform float line_pos = 0.5;
uniform vec4 edge_color : source_color = vec4(0.95, 0.97, 1.0, 1.0);
uniform float edge_width = 0.006;

void fragment() {
	// Coordonnée le long de la normale de la lame. L'inclinaison donne à la
	// séparation son mouvement : une barre verticale sèche ferait volet
	// coulissant, une diagonale fait coupe de montage.
	float axis = UV.x + (UV.y - 0.5) * slant;

	// La lame part au-delà du bord droit et vient se poser à sa place : la
	// séparation ENTRE dans l'image au lieu d'apparaître.
	float line = mix(1.35, line_pos, split_amount);

	float d = axis - line;
	// Anticrénelage du bord, en pixels écran.
	float aa = fwidth(axis) * 1.2;

	// Côté droit de la lame : la vue du poursuivant.
	float other = smoothstep(-aa, aa, d);
	vec4 view = texture(other_view, vec2((UV.x - slice_u0) / slice_w, UV.y));

	// Lame lumineuse : un cœur net et un halo, dont l'intensité suit
	// l'ouverture pour que l'apparition ne soit pas brutale.
	float core = 1.0 - smoothstep(0.0, edge_width, abs(d));
	float halo = 1.0 - smoothstep(0.0, edge_width * 7.0, abs(d));
	float glow = (core + halo * 0.35) * clamp(split_amount * 2.0, 0.0, 1.0);

	// COMPOSITION EXACTE — deux couches, pas une moyenne.
	//
	// Il y a deux choses à poser sur l'image du dessous : la vue du volet, qui
	// ne couvre que le côté droit de la lame (`other`), et la lame lumineuse,
	// qui couvre les deux côtés (`glow`).
	//
	// Écrire `mix(view, edge, glow)` avec une opacité de `glow` mélangeait les
	// deux : à GAUCHE de la lame, où `other` vaut zéro et où le volet ne doit
	// donc rien afficher, le halo peignait quand même les deux tiers de
	// l'image de l'autre volet. Les lignes de piste du volet voisin
	// transparaissaient dans le halo — elles semblaient déborder par-dessus la
	// séparation.
	//
	// La bonne formule empile les couches au lieu de les moyenner :
	//   résultat = lame·glow + vue·other·(1−glow) + fond·(1−glow)(1−other)
	// d'où l'opacité et la couleur ci-dessous.
	float g = clamp(glow, 0.0, 1.0);
	float coverage = 1.0 - (1.0 - g) * (1.0 - other);
	vec3 stacked = edge_color.rgb * g + view.rgb * other * (1.0 - g);
	COLOR = vec4(coverage > 0.0001 ? stacked / coverage : edge_color.rgb, coverage);
}
