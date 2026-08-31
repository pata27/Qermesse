// Piste de vélodrome — docs/04 §1 et §2.
//
// Tout est procédural : couloirs, arêtes néon, bandes défilantes. Aucune texture
// dans le dépôt, donc aucun asset à laisser orphelin — c'est la leçon de la v2,
// qui embarquait un jeu complet d'images jamais référencées.
//
// La couleur de chaque couloir vient du roster : elle est passée en uniforme,
// jamais codée en dur.
shader_type spatial;
render_mode cull_disabled, specular_schlick_ggx;

uniform vec3 track_color : source_color = vec3(0.086, 0.106, 0.149);
uniform vec4 lane_colors[4];
uniform int lane_count = 2;
uniform float lane_width = 1.6;

// Position de l'ancre le long de la piste, en mètres. Les bandes défilent avec
// elle : le monde est statique, c'est la caméra qui avance.
uniform float anchor_m = 0.0;
uniform float band_period_m = 8.0;
uniform float band_intensity = 1.0;

// Ligne d'arrivée, en coordonnée relative à l'ancre. Négatif = pas de ligne.
uniform float finish_z = -1000.0;
uniform float glow_boost = 1.0;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

// Largeur d'un trait constante à l'écran quelle que soit la distance : sans
// cela les arêtes néon disparaissent au loin et scintillent de près.
float crisp_line(float coord, float target, float half_width) {
	float d = abs(coord - target);
	float aa = fwidth(coord) * 1.5;
	return 1.0 - smoothstep(half_width, half_width + aa, d);
}

void fragment() {
	float total_width = float(lane_count) * lane_width;
	float x = world_pos.x + total_width * 0.5;
	float z = world_pos.z + anchor_m;

	vec3 color = track_color;
	float emission = 0.0;
	vec3 emission_color = vec3(0.0);

	// Atténuation avec la distance : sans elle, les néons filent jusqu'à
	// l'horizon en traits saturés et l'image devient agressive. Retour de
	// l'utilisateur : « ça pique les yeux ».
	float depth = length(world_pos - CAMERA_POSITION_WORLD);
	float falloff = 1.0 - smoothstep(12.0, 95.0, depth);

	// Séparateurs de couloir, teintés par la couleur du rider de gauche.
	for (int i = 0; i <= lane_count; i++) {
		float edge = float(i) * lane_width;
		float line = crisp_line(x, edge, 0.030);
		if (line > 0.001) {
			int tint = clamp(i == lane_count ? i - 1 : i, 0, 3);
			emission_color = mix(emission_color, lane_colors[tint].rgb, line);
			emission = max(emission, line * 0.34 * falloff);
		}
	}

	// Bandes transversales : c'est elles qui donnent la sensation de vitesse.
	// Leur cadence est fixe en mètres, donc leur défilement EST la vitesse.
	float band = fract(z / band_period_m);
	float band_line = 1.0 - smoothstep(0.02, 0.05, min(band, 1.0 - band));
	if (x > 0.0 && x < total_width) {
		// Les bandes sont l'indice principal de vitesse : nettes de près, où le
		// défilement se lit, éteintes au loin.
		emission = max(emission, band_line * 0.30 * band_intensity * falloff);
		emission_color = mix(emission_color, vec3(0.60, 0.78, 1.0), band_line * 0.7);
		color = mix(color, color * 1.6, band_line * 0.5);
	}

	// Ligne d'arrivée : damier, visible de loin (docs/04 §4).
	float to_finish = abs(world_pos.z - finish_z);
	if (finish_z > -999.0 && to_finish < 0.6 && x > 0.0 && x < total_width) {
		float checker = step(0.5, fract(x * 1.5));
		color = mix(vec3(0.05), vec3(0.95), checker);
		emission = max(emission, 0.35);
		emission_color = mix(emission_color, vec3(1.0), 0.7);
	}

	// Assombrissement hors piste : le regard doit tomber sur les couloirs.
	float outside = 1.0 - step(0.0, x) * step(x, total_width);
	color = mix(color, track_color * 0.35, outside);

	ALBEDO = color;
	ROUGHNESS = 0.75;
	METALLIC = 0.0;
	EMISSION = emission_color * emission * glow_boost;
}
