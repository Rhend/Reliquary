# ============================================================
# CycleData.gd — Passage de données entre scènes de cycle.
#
# Stocke temporairement le résumé du dernier cycle terminé
# pour que CycleSummaryScreen puisse le lire sans référence
# directe à AdventureSystem ou Biome.
# ============================================================
extends Node

var last_cycle_summary: Dictionary = {}
