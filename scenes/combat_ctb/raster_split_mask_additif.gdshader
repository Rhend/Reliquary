// ============================================================
// raster_split_mask_additif.gdshader — même écrêtage que raster_split_mask.gdshader
// (voir ce fichier pour le pourquoi de la coupure), mais en rendu ADDITIF : pour
// les VFX du décor adverse (étincelles de soudure, etc.) qui doivent brûler comme
// une vraie source de lumière plutôt que se poser en autocollant plat — même
// raisonnement que NeonRunners côté ville. Fichier séparé et non un paramètre du
// shader existant : `render_mode` est figé dans le CODE du shader, partagé par
// TOUTE instance de ShaderMaterial qui le référence — un seul uniforme ne peut
// pas faire varier le blend mode entre le décor opaque (Sol, Armature, Soudeur…)
// et un VFX ponctuel sans casser les premiers.
// ============================================================
shader_type canvas_item;
render_mode blend_add;

uniform float split_tilt = 0.0625;   // bande VS / largeur — CombatDecorFactory.construire()

void fragment() {
	float d = (SCREEN_UV.x - 0.5) + split_tilt * (SCREEN_UV.y - 0.5);
	float s = smoothstep(-0.012, 0.012, d);   // 0 = héros (gauche), 1 = adverse (droite)
	COLOR.a *= s;
}
