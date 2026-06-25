// ============================================================
// holo_traffic.gdshader - Trafic : traînées lumineuses le long des routes.
//
// Appliqué à un mesh de courts segments (PRIMITIVE_LINES), un par « voiture ».
// UV.x = phase [0,1] ; UV2 = vecteur de trajet COMPLET (longueur de la route,
// orientation) ; COLOR.rgb = couleur (cyan = aller, ambre = retour). Le vertex
// shader translate le segment le long du trajet selon TIME (boucle via fract).
// Additif, sans écriture de profondeur, avec la même brume de profondeur que
// le reste. IMPORTANT : commentaires ASCII pur.
// ============================================================
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform float vitesse = 0.08;     // tours/seconde (lent)
uniform float emission = 2.2;     // glint lumineux (glow)
uniform float fog_debut = 16.0;
uniform float fog_fin = 30.0;
uniform float fog_min = 0.25;

varying vec3 w_pos;
varying float v_a;

void vertex() {
	float t = fract(UV.x + TIME * vitesse);
	VERTEX.x += UV2.x * t;
	VERTEX.z += UV2.y * t;
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Fondu aux extrémités de boucle : pas de pop au bout de la route.
	v_a = smoothstep(0.0, 0.05, t) * (1.0 - smoothstep(0.93, 1.0, t));
}

void fragment() {
	float d = distance(w_pos, CAMERA_POSITION_WORLD);
	float fade = mix(1.0, fog_min, smoothstep(fog_debut, fog_fin, d));
	vec3 c = COLOR.rgb * emission * fade;
	ALBEDO = c;
	EMISSION = c;
	ALPHA = v_a * fade;
}
