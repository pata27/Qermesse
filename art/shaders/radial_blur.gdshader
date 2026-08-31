// Flou radial périphérique — docs/04 §4.
//
// Le SEUL effet qui a besoin de relire l'image, donc le seul qui paie une copie
// du tampon d'écran. Il n'est actif qu'au niveau de qualité « eleve » et
// au-delà d'un seuil de vitesse : le reste du temps, le noeud est masqué et
// aucune copie n'a lieu.
shader_type canvas_item;
render_mode blend_mix;

uniform float strength = 0.0;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear;

void fragment() {
	vec2 centered = UV - vec2(0.5);
	float edge = smoothstep(0.45, 1.05, length(centered) * 2.0);
	if (strength * edge < 0.004) {
		// Rien à faire au centre : on laisse l'image intacte.
		COLOR = vec4(0.0);
	} else {
		vec3 blurred = vec3(0.0);
		float amount = strength * edge * 0.035;
		for (int i = 0; i < 6; i++) {
			float t = float(i) / 5.0;
			blurred += texture(screen_texture, SCREEN_UV - centered * amount * t).rgb;
		}
		COLOR = vec4(blurred / 6.0, edge * strength);
	}
}
