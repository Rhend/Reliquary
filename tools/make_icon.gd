# ============================================================
# make_icon.gd — Générateur d'icône d'application (DEV).
#
# Rasterise une icône SVG (flèche d'évolution, dégradé de rareté du jeu)
# via le moteur SVG de Godot, puis empaquette plusieurs résolutions dans
# un .ico multi-tailles utilisable par l'export Windows.
#
#   godot --headless --path . --script res://tools/make_icon.gd
#
# Sorties :
#   res://icon.ico                  → à pointer dans le preset d'export
#   res://tools/_icon_preview.png   → aperçu 256px (git-ignoré)
# ============================================================
extends SceneTree

# PNG-in-ICO (Vista+) : chaque taille est un PNG complet embarqué dans le .ico.
const SIZES := [256, 128, 64, 48, 32, 16]

# Chevrons de rang empilés = montée en rareté : vert Peu Commun (bas) → bleu
# Rare → violet Épique → or Légendaire (haut). Couleurs alignées sur UIColors.
const SVG := """<svg xmlns="http://www.w3.org/2000/svg" width="256" height="256" viewBox="0 0 256 256">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="256" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#141826"/>
      <stop offset="1" stop-color="#080a11"/>
    </linearGradient>
    <radialGradient id="glow" cx="128" cy="128" r="112" gradientUnits="userSpaceOnUse">
      <stop offset="0" stop-color="#8ad6ff" stop-opacity="0.34"/>
      <stop offset="0.55" stop-color="#3a5a7d" stop-opacity="0.14"/>
      <stop offset="1" stop-color="#000000" stop-opacity="0"/>
    </radialGradient>
  </defs>
  <rect x="6" y="6" width="244" height="244" rx="54" fill="url(#bg)"/>
  <ellipse cx="128" cy="128" rx="106" ry="106" fill="url(#glow)"/>
  <g stroke="#ffffff" stroke-opacity="0.16" stroke-width="1.4" stroke-linejoin="round">
    <path d="M58 198 L128 152 L198 198 L198 224 L128 178 L58 224 Z" fill="#38d161"/>
    <path d="M58 158 L128 112 L198 158 L198 184 L128 138 L58 184 Z" fill="#3894ff"/>
    <path d="M58 118 L128 72 L198 118 L198 144 L128 98 L58 144 Z" fill="#b847ff"/>
    <path d="M58 78 L128 32 L198 78 L198 104 L128 58 L58 104 Z" fill="#ffc714"/>
  </g>
  <rect x="6" y="6" width="244" height="244" rx="54" fill="none" stroke="#3894ff" stroke-opacity="0.22" stroke-width="2"/>
</svg>"""

func _initialize() -> void:
	var pngs: Array = []
	for s in SIZES:
		var img := Image.new()
		var err := img.load_svg_from_string(SVG, float(s) / 256.0)
		if err != OK:
			push_error("Echec rasterisation SVG @%dpx (err %d)" % [s, err])
			quit(1)
			return
		if img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
		pngs.append(img.save_png_to_buffer())
		if s == 256:
			img.save_png("res://tools/_icon_preview.png")

	var f := FileAccess.open("res://icon.ico", FileAccess.WRITE)
	if f == null:
		push_error("Impossible d'ouvrir res://icon.ico en ecriture")
		quit(1)
		return
	# ICONDIR
	f.store_16(0)               # reserved
	f.store_16(1)               # type = icône
	f.store_16(SIZES.size())    # nombre d'images
	# ICONDIRENTRY × N
	var offset := 6 + 16 * SIZES.size()
	for i in SIZES.size():
		var s: int = SIZES[i]
		var dim := 0 if s >= 256 else s   # 0 encode 256 dans le format ICO
		f.store_8(dim)                    # largeur
		f.store_8(dim)                    # hauteur
		f.store_8(0)                      # palette
		f.store_8(0)                      # reserved
		f.store_16(1)                     # plans
		f.store_16(32)                    # bits/pixel
		f.store_32((pngs[i] as PackedByteArray).size())
		f.store_32(offset)
		offset += (pngs[i] as PackedByteArray).size()
	# Données PNG concaténées
	for p in pngs:
		f.store_buffer(p as PackedByteArray)
	f.close()

	print("icon.ico genere — tailles: ", SIZES)
	quit(0)
