// ============================================================
// holo_route.gdshader - Routes-neon au sol avec flux lumineux qui circule.
//
// Applique au mesh des routes (PRIMITIVE_LINES). Chaque route porte sa
// distance le long du trace dans UV.x ; un pic lumineux se deplace le long de
// l'axe (flux de donnees) selon TIME. La vertex color.a porte la hierarchie
// (grand axe = plus marque, rue secondaire = plus discret). Emission additive
// HDR sous controle pour rester sous les lieux en luminosite.
//
// IMPORTANT : commentaires ASCII pur (parseur de shaders Godot).
// ============================================================
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4  route_color : source_color = vec4(0.95, 0.30, 0.66, 1.0); // magenta rose (distinct du violet Epique)
uniform float emission_base = 0.5;    // neon de base (discret)
uniform float flux_intensite = 1.2;   // surbrillance du flux
uniform float flux_vitesse = 0.35;    // vitesse du flux (lent)
uniform float flux_frequence = 0.18;  // pulses par unite de longueur
// Brume de profondeur (coherente avec holo_line).
uniform float fog_debut = 16.0;
uniform float fog_fin = 30.0;
uniform float fog_min = 0.25;

varying vec3 w_pos;

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float u = UV.x;
	float phase = fract(u * flux_frequence - TIME * flux_vitesse);
	float pulse = exp(-pow((phase - 0.5) / 0.07, 2.0));  // pic etroit qui se deplace
	float inten = COLOR.a;                               // hierarchie avenue / rue
	float d = distance(w_pos, CAMERA_POSITION_WORLD);
	float fade = mix(1.0, fog_min, smoothstep(fog_debut, fog_fin, d));
	vec3 c = route_color.rgb * inten * (emission_base + flux_intensite * pulse) * fade;
	ALBEDO = c;
	EMISSION = c;
	ALPHA = fade;
}
