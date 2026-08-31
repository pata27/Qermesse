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

void vertex() {
	// Billboard : la face reste tournée vers la caméra.
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
		INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);

	// Chaque spectateur a sa propre phase, tirée de sa position : sans cela la
	// tribune ondule comme un seul bloc, ce qui se voit immédiatement.
	float phase = MODEL_MATRIX[3].x * 3.7 + MODEL_MATRIX[3].z * 1.9;
	float bob = sin(TIME * (2.2 + excitement * 5.0) + phase);
	VERTEX.y += bob * (0.05 + excitement * 0.28) * (UV.y < 0.5 ? 1.0 : 0.2);
}

void fragment() {
	// Silhouette : buste arrondi, pas de détail. À cette distance, seule la
	// masse compte.
	vec2 p = UV * 2.0 - 1.0;
	float body = 1.0 - smoothstep(0.55, 0.85, length(vec2(p.x, (p.y + 0.25) * 0.75)));
	if (body < 0.05) {
		discard;
	}
	float lift = 0.55 + excitement * 0.65;
	ALBEDO = crowd_tint.rgb * lift;
	EMISSION = crowd_tint.rgb * excitement * 0.5;
}
