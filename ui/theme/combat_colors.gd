# ============================================================
# CombatColors — Palette centralisée pour les FX de combat.
# Accessible via le class_name : CombatColors.HERO_BORDER_COLOR
# ============================================================
class_name CombatColors

# ── Liserets de camp ─────────────────────────────────────────
const HERO_BORDER_COLOR  := Color("#8B5CF6")   # violet
const ENEMY_BORDER_COLOR := Color("#DC2626")   # rouge

# ── Glow (liseret illuminé lors de l'attaque) ────────────────
const HERO_GLOW_COLOR  := Color("#A78BFA")   # violet saturé
const ENEMY_GLOW_COLOR := Color("#F87171")   # rouge saturé

# ── Halo diffus (autour du panel actif, alpha réduit) ────────
const HERO_HALO_COLOR  := Color(0.545, 0.361, 0.984, 0.45)
const ENEMY_HALO_COLOR := Color(0.984, 0.380, 0.380, 0.45)

# ── Épaisseurs de liseret ────────────────────────────────────
const BORDER_IDLE: int  = 2
const BORDER_GLOW: int  = 4
