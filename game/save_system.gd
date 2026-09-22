# save_system.gd
# Versioned deterministic save. Procedural chunks are never serialized.
class_name SaveSystem
extends RefCounted

const DEFAULT_PATH := "user://star_hollow_save.json"

static func save_game(gs: GameState, path: String = DEFAULT_PATH) -> bool:
	if gs == null or gs.planet == null:
		return false
	var player_pos := gs.player.global_position if gs.player != null else Vector2.ZERO
	var payload := {
		"format_version": 1,
		"generator_version": SciConstants.WORLD_GENERATOR_VERSION,
		"planet": {
			"preset": gs.planet.preset,
			"seed": gs.planet.seed,
			"name": gs.planet.name,
		},
		"player_position": [player_pos.x, player_pos.y],
		"discoveries": gs.discovery.export_state(),
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("SaveSystem: cannot open %s for writing" % path)
		return false
	file.store_string(JSON.stringify(payload))
	return true

static func load_game(gs: GameState, path: String = DEFAULT_PATH) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "reason": "missing"}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "reason": "open_failed"}
	var parsed = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		return {"ok": false, "reason": "invalid_json"}
	var data: Dictionary = parsed
	var saved_gen := int(data.get("generator_version", -1))
	if saved_gen != SciConstants.WORLD_GENERATOR_VERSION:
		return {
			"ok": false,
			"reason": "generator_version_mismatch",
			"saved_generator_version": saved_gen,
			"current_generator_version": SciConstants.WORLD_GENERATOR_VERSION,
		}
	var planet_data: Dictionary = data.get("planet", {})
	var seed_value := int(planet_data.get("seed", 1))
	var preset := String(planet_data.get("preset", ""))
	if preset != "":
		gs.init_planet(preset, seed_value)
	else:
		gs.init_random_planet(seed_value)
	gs.discovery.import_state(data.get("discoveries", {}))
	var raw_pos = data.get("player_position", [0.0, 0.0])
	var pos := Vector2.ZERO
	if raw_pos is Array and raw_pos.size() >= 2:
		pos = Vector2(float(raw_pos[0]), float(raw_pos[1]))
	if gs.player != null:
		gs.player.global_position = pos
	return {"ok": true, "player_position": pos}
