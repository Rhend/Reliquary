// ============================================================
// raster_split_mask.gdshader — écrête un calque raster à la moitié ADVERSE de
// l'écran (même diagonale que le séparateur VS), pour qu'il ne recouvre pas le
// décor héros dessiné en dessous (CombatFondScinde). Même formule que le
// split de biome_background.gdshader (BiomeBackground.set_split, side = 2),
// réduite à ce seul cas et basée sur SCREEN_UV plutôt que sur l'UV locale :
// plus simple pour un décor fait de nombreux Sprite2D indépendants (ribbon de
// défilement), au prix d'une diagonale figée en espace écran pendant le
// zoom-duel (négligeable : bref, et la coupure holographique masque déjà le
// mince fondu résiduel autour de l'axe).
// ============================================================
shader_type canvas_item;

uniform float split_tilt = 0.0625;   // bande VS / largeur — CombatDecorFactory.construire()

void fragment() {
	float d = (SCREEN_UV.x - 0.5) + split_tilt * (SCREEN_UV.y - 0.5);
	float s = smoothstep(-0.012, 0.012, d);   // 0 = héros (gauche), 1 = adverse (droite)
	COLOR.a *= s;
}
