// ============================================================
// holo_fumee.gdshader - Panache de fumée holographique (volutes molles).
//
// Applique a un mesh de QUADS (PRIMITIVE_TRIANGLES). Chaque bouffee = 4 sommets
// places au MEME point (le sommet de cheminee), avec :
//   UV.x  = phase de la bouffee (0..1), UV.y = taille de base,
//   UV2   = coin du billboard dans [-1,1]^2, COLOR.a = densite de base.
// Le vertex shader fait monter la bouffee selon TIME (boucle via fract), la fait
// GONFLER en montant, et l'oriente face camera (billboard). Le fragment dessine un
// disque doux a chute radiale → amas de volutes rondes, pas des traits.
//
// Additif, sans ecriture de profondeur. Commentaires ASCII pur (parseur Godot).
// ============================================================
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4  fumee_color : source_color = vec4(0.50, 0.58, 0.28, 1.0);
uniform float vitesse = 0.05;     // vitesse de montee (lente)
uniform float hauteur = 1.3;      // hauteur de montee avant boucle
uniform float expansion = 1.8;    // facteur de grossissement en montant

varying float v_fade;
varying vec2  v_uv;

void vertex() {
	float t = fract(UV.x + TIME * vitesse);
	float r = UV.y * (0.45 + expansion * t);              // grossit en montant
	vec3 center = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	center.y += t * hauteur;
	vec3 right = INV_VIEW_MATRIX[0].xyz;                  // base camera (billboard)
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	vec3 wpos = center + right * (UV2.x * r) + up * (UV2.y * r);
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(wpos, 1.0);
	// Fondu d'entree (bas) et de sortie (haut) → boucle invisible.
	v_fade = smoothstep(0.0, 0.16, t) * (1.0 - smoothstep(0.55, 1.0, t));
	v_uv = UV2;
}

void fragment() {
	float d = length(v_uv);
	float soft = smoothstep(1.0, 0.0, d);   // 1 au centre, 0 au bord → disque doux
	soft *= soft;                            // bord encore plus flou (volute)
	vec3 c = fumee_color.rgb;
	ALBEDO = c;
	EMISSION = c * soft;
	ALPHA = COLOR.a * soft * v_fade;
}
