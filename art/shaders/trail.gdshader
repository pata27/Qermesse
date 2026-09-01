// Traînée lumineuse derrière un rider — docs/04 §4.
//
// Longueur et intensité proportionnelles à la vitesse : c'est l'effet qui porte
// la sensation, pas la géométrie.
// Mélange ALPHA et non additif : en additif, une traînée un peu dense sature
// les trois canaux et vire au blanc — elle perdait la couleur du rider, qui est
// pourtant son unique raison d'être.
shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded, depth_draw_never;

uniform vec4 trail_color : source_color = vec4(0.0, 0.898, 1.0, 1.0);
uniform float intensity = 1.0;

void fragment() {
	// UV.y va de 0 au rider à 1 au bout de la traînée ; UV.x monte du sol vers
	// le haut de l'aileron.
	float along = 1.0 - UV.y;
	// Dense au ras du sol, dissipée vers le haut.
	float height_fade = pow(1.0 - UV.x, 1.4);
	float shape = pow(along, 1.5) * height_fade;
	// Couleur pure et saturée, opacité modérée : c'est l'ALPHA qui module,
	// jamais la luminance.
	ALBEDO = trail_color.rgb;
	EMISSION = trail_color.rgb * 0.9;
	ALPHA = clamp(shape * intensity * 0.85, 0.0, 1.0);
}
