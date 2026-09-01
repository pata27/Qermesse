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

// Bois clair d'un vélodrome, assombri par l'éclairage nocturne. Nettement plus
// clair que l'anthracite du fond : c'est ce contraste qui fait exister le sol.
uniform vec3 track_color : source_color = vec3(0.30, 0.235, 0.175);
uniform vec4 lane_colors[4];
uniform int lane_count = 2;
uniform float lane_width = 1.6;

// Position de l'ancre le long de la piste, en mètres. Les bandes défilent avec
// elle : le monde est statique, c'est la caméra qui avance.
uniform float anchor_m = 0.0;
// Cinq mètres : à huit, aucun repère ne tombait dans le premier plan, là
// précisément où le défilement se lit. C'est la cadence de passage des repères
// QUI EST la sensation de vitesse.
uniform float band_period_m = 5.0;
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

	// Atténuation avec la distance. Sans elle, les néons filent jusqu'à
	// l'horizon en traits saturés et l'image devient agressive.
	float depth = length(world_pos - CAMERA_POSITION_WORLD);
	float falloff = 1.0 - smoothstep(12.0, 95.0, depth);
	bool on_track = x > 0.0 && x < total_width;

	// =====================================================================
	// 1. LA SURFACE — d'abord, toujours.
	//
	// L'ordre compte, et il a coûté deux itérations : la surface était
	// calculée APRÈS les marquages et les effaçait tous. Repères de distance
	// et ligne d'arrivée étaient invisibles, et le réglage de leur intensité
	// ne pouvait évidemment rien y changer.
	// =====================================================================
	float plank = fract(x / 0.19);
	float seam_width = mix(0.10, 0.5, smoothstep(20.0, 90.0, depth));
	float seam = 1.0 - smoothstep(0.0, seam_width, min(plank, 1.0 - plank));
	float plank_id = floor(x / 0.19);
	float grain = fract(sin(plank_id * 12.9898) * 43758.5453);
	vec3 wood = track_color * (0.88 + grain * 0.30);
	wood *= 1.0 - seam * 0.45;
	float vein = fract(sin(plank_id * 78.233 + floor(z * 0.7)) * 43758.5453);
	wood *= 0.94 + vein * 0.12;

	// Hors piste, le bois s'assombrit AVEC LA DISTANCE À LA PISTE. Un plat
	// extérieur aussi lumineux que les couloirs attire l'œil pour rien et
	// laisse un tiers de l'image occupé par du vide clair.
	float off = max(0.0, max(-x, x - total_width));
	float outside_dim = mix(0.34, 0.055, smoothstep(0.0, 5.0, off));
	vec3 color = on_track ? wood : wood * outside_dim;

	// Côte d'azur : la bande bleue au pied de la piste, le signe qui dit
	// « vélodrome » d'un coup d'œil.
	float apron = 0.45;
	if ((x < 0.0 && x > -apron) || (x > total_width && x < total_width + apron)) {
		color = vec3(0.055, 0.115, 0.175) * (0.45 + 0.55 * falloff);
	}

	// =====================================================================
	// 2. LES MARQUAGES — peints PAR-DESSUS la surface.
	// =====================================================================
	float emission = 0.0;
	vec3 emission_color = vec3(0.0);

	// Ligne des sprinters : bordeaux sombre et fin, pour ne pas disputer sa
	// teinte à la couleur d'un couloir (docs/03 §6).
	float sprinters = crisp_line(x, total_width * 0.32, 0.022);
	if (sprinters > 0.001 && on_track) {
		color = mix(color, vec3(0.34, 0.09, 0.10), sprinters * 0.85);
	}

	// Repères de distance, avec un repère appuyé tous les cinq : un rythme
	// régulier sans accent ne se compte pas.
	float band_pos = z / band_period_m;
	float band_edge = min(fract(band_pos), 1.0 - fract(band_pos));
	float band_aa = fwidth(band_pos) * 1.5;
	float band_line = 1.0 - smoothstep(0.020, 0.020 + band_aa + 0.02, band_edge);
	float major = 1.0 - step(0.001, abs(floor(band_pos) - floor(band_pos / 5.0) * 5.0));
	float band_strength = band_line * mix(0.55, 1.0, major);
	if (on_track) {
		// Peinture blanche mate : l'albédo porte le repère, l'émission ne sert
		// qu'à l'accroche lointaine. Trop d'émission de près en faisait une
		// poutre lumineuse en travers de la piste.
		color = mix(color, vec3(0.88, 0.87, 0.84), band_strength * 0.92);
		float band_glow = band_strength * 0.14 * band_intensity * falloff;
		emission = max(emission, band_glow);
		emission_color = mix(emission_color, vec3(0.80, 0.86, 1.0), band_glow * 2.5);
	}

	// Ligne d'arrivée : damier, visible de loin (docs/04 §4).
	float to_finish = abs(world_pos.z - finish_z);
	if (finish_z > -999.0 && to_finish < 0.6 && on_track) {
		float checker = step(0.5, fract(x * 1.5));
		color = mix(vec3(0.05), vec3(0.95), checker);
		emission = max(emission, 0.30);
		emission_color = mix(emission_color, vec3(1.0), 0.7);
	}

	// Bordure extérieure : sans elle, la piste se dissout dans le noir.
	float kerb = max(crisp_line(x, -apron, 0.045), crisp_line(x, total_width + apron, 0.045));
	if (kerb > 0.001) {
		color = mix(color, vec3(0.72, 0.76, 0.82), kerb);
		emission = max(emission, kerb * 0.10 * falloff);
		emission_color = mix(emission_color, vec3(0.7, 0.8, 1.0), kerb);
	}

	// =====================================================================
	// 3. LES NÉONS DE COULOIR — l'identité de chaque rider.
	// =====================================================================
	for (int i = 0; i <= lane_count; i++) {
		float edge = float(i) * lane_width;
		int tint = clamp(i == lane_count ? i - 1 : i, 0, 3);

		// Retombée sur le parquet : un tube de néon éclaire le sol autour de
		// lui. Sans cette nappe, les lignes flottaient au-dessus d'un bois
		// mort et la scène n'avait aucune unité lumineuse.
		float spill = 1.0 - smoothstep(0.0, 0.55, abs(x - edge));
		spill *= spill * falloff;
		color += lane_colors[tint].rgb * spill * 0.16;

		float line = crisp_line(x, edge, 0.030);
		if (line > 0.001) {
			emission_color = mix(emission_color, lane_colors[tint].rgb, line);
			emission = max(emission, line * 0.75 * falloff);
		}
	}

	ALBEDO = color;
	// Bois mat : un spéculaire marqué transformait les relevés en surfaces
	// laquées et les faisait ressortir en gris clair.
	ROUGHNESS = 0.88;
	METALLIC = 0.0;
	SPECULAR = 0.12;
	EMISSION = emission_color * emission * glow_boost;
}
