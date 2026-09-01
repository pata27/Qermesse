// Vignettage et lignes de vitesse — docs/04 §4.
//
// **Ce shader ne lit JAMAIS le tampon d'écran.** C'est tout l'intérêt : un
// `hint_screen_texture` force Godot à recopier l'image complète avant chaque
// dessin, soit huit mégaoctets par image en 1080p, y compris quand l'effet est
// à intensité nulle. Ici, le vignettage et les traits sont composés
// analytiquement — coût nul quand `intensity` vaut zéro.
shader_type canvas_item;
render_mode blend_mix;

uniform float intensity = 0.0;
uniform float vignette = 0.55;
uniform vec4 line_color : source_color = vec4(0.85, 0.93, 1.0, 1.0);

float hash(float n) {
	return fract(sin(n) * 43758.5453123);
}

void fragment() {
	vec2 centered = UV - vec2(0.5);
	float radius = length(centered) * 2.0;
	float edge = smoothstep(0.45, 1.05, radius);

	// Vignettage : assombrit les bords, en multiplicatif.
	float darken = smoothstep(0.75, 1.5, radius) * vignette;

	vec3 add = vec3(0.0);
	if (intensity > 0.001) {
		float angle = atan(centered.y, centered.x);
		float slot = floor(angle * 24.0 / 6.2831853 + 0.5);
		float jitter = hash(slot);
		float streak = smoothstep(0.965, 1.0, cos(angle * 24.0 - jitter * 6.28));
		float travel = fract(radius * 1.6 - TIME * (1.4 + jitter));
		streak *= smoothstep(0.0, 0.35, travel) * (1.0 - smoothstep(0.55, 1.0, travel));
		add = line_color.rgb * streak * edge * intensity * 0.45;
	}

	// Un seul quad, deux effets : on assombrit par l'alpha et on ajoute les
	// traits par la couleur.
	COLOR = vec4(add, max(darken, dot(add, vec3(0.333))));
}
