// Foule en billboards instanciés — docs/04 §4.
//
// Un MultiMesh d'un seul quad : deux mille spectateurs pour un appel de rendu.
// Sur un GPU intégré, c'est la seule façon de peupler des tribunes sans manger
// le budget des 60 fps.
shader_type spatial;
render_mode cull_disabled, unshaded;

uniform vec4 crowd_tint : source_color = vec4(0.18, 0.22, 0.32, 1.0);
uniform float time_offset = 0.0;
// Monte au franchissement et à l'accélération : la foule RÉAGIT.
uniform float excitement = 0.0;
// Distance parcourue par le peloton, en mètres, et longueur du tronçon peuplé.
// Le défilement de la foule se fait ICI, spectateur par spectateur.
uniform float scroll_m = 0.0;
uniform float span_m = 560.0;

void vertex() {
	// DÉFILEMENT PAR INSTANCE, et non par translation du noeud entier.
	//
	// Tout le décor périodique — poteaux, poutres, marquages — défile en
	// décalant son noeud de `-fposmod(ancre, 10 m)`. C'est invisible tant que
	// les objets sont espacés de dix mètres exactement : le décalage revient
	// alors sur un motif identique. Les spectateurs, eux, sont répartis au
	// HASARD : à chaque tour de modulo, la tribune entière se téléportait de
	// dix mètres en arrière. D'où des sauts, et l'impression que la foule
	// n'avançait pas avec le reste.
	//
	// Chaque spectateur reboucle donc pour son propre compte, sur toute la
	// longueur du tronçon. Le saut existe toujours, mais il ne concerne qu'un
	// spectateur à la fois, et il a lieu à l'extrémité du tronçon — dans la
	// brume, hors de vue.
	vec4 origin = MODEL_MATRIX[3];
	origin.z = mod(origin.z - scroll_m + span_m * 0.5, span_m) - span_m * 0.5;

	// Billboard : la face reste tournée vers la caméra.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], origin);

	// Phase tirée de l'IDENTIFIANT d'instance, et surtout PAS de la position
	// monde. Depuis que le décor défile, cette position change à chaque image :
	// la phase sautait donc en permanence et les spectateurs se réarrangeaient
	// au hasard plusieurs fois par seconde.
	float phase = float(INSTANCE_ID) * 0.7391;
	float bob = sin(TIME * (2.2 + excitement * 5.0) + phase);
	VERTEX.y += bob * (0.05 + excitement * 0.28) * (UV.y < 0.5 ? 1.0 : 0.2);
}

void fragment() {
	// Silhouette tête + épaules. Un simple ovale donnait des galets ; deux
	// formes suffisent à faire lire « quelqu'un d'assis ».
	vec2 p = UV * 2.0 - 1.0;
	// Tête : petit disque en haut.
	float head = 1.0 - smoothstep(0.26, 0.34, length(vec2(p.x * 1.5, p.y + 0.62)));
	// Buste : ovale large en bas.
	float torso = 1.0 - smoothstep(0.78, 0.92, length(vec2(p.x * 0.95, (p.y - 0.35) * 0.85)));
	float body = max(head, torso);
	if (body < 0.05) {
		discard;
	}
	float lift = 0.55 + excitement * 0.65;
	ALBEDO = crowd_tint.rgb * lift;
	EMISSION = crowd_tint.rgb * excitement * 0.5;
}
