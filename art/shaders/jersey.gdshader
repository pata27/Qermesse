// Cycliste — docs/04 §4.
//
// **Le corps est ÉCLAIRÉ, il n'émet presque pas.** C'était l'erreur de la
// première version : un matériau fortement émissif n'a aucun ombrage, donc
// toute forme pleine devient un aplat de couleur uniforme. Le vélo se lisait
// parce qu'il est fait de traits fins ; le cycliste ressortait en « grosse
// patate ». Retour de l'utilisateur, consigné dans `tasks/lessons.md`.
//
// La couleur du couloir reste portée par le maillot, mais c'est la lumière qui
// donne le volume et un liseré qui détache la silhouette du fond.
shader_type spatial;

uniform vec4 jersey_color : source_color = vec4(0.0, 0.898, 1.0, 1.0);
// Volontairement faible. Au-delà de ~0.35 la forme s'aplatit.
uniform float emission_energy = 0.22;
uniform float rim_energy = 1.5;
// Grisé quand le rider est éliminé — docs/02 §3.
uniform float dimmed = 0.0;
// Pulse au franchissement de la ligne.
uniform float highlight = 0.0;

void fragment() {
	vec3 base = jersey_color.rgb;

	// Liseré sur les faces rasantes : il dessine le contour du corps, ce qui
	// est exactement ce qui manquait pour lire une silhouette.
	float rim = pow(1.0 - abs(dot(NORMAL, VIEW)), 3.0);

	vec3 albedo = mix(base * 0.55, vec3(0.42), dimmed * 0.8);
	float energy = emission_energy * mix(1.0, 0.15, dimmed) + highlight * 2.5;

	ALBEDO = albedo;
	// L'émission sert au liseré, pas à la masse : le corps reste ombré.
	EMISSION = base * (energy + rim * rim_energy * mix(1.0, 0.2, dimmed));
	ROUGHNESS = 0.42;
	METALLIC = 0.0;
	SPECULAR = 0.6;
}
