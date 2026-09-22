# game_state.gd
# -----------------------------------------------------------------------------
# Autoload singleton holding the full game state: planet, solver, discovery,
# chunk cache, sample history, and references to UI nodes.
# -----------------------------------------------------------------------------
class_name GameState
extends Node

const CHUNK_LOAD_RADIUS := 2

var planet: PlanetParameters
var solver: CoupledPlanetSolver
var discovery: DiscoverySystem
var chunk_map: Dictionary
var sample_history: Array
var player: Node2D
var hud: Control
var debug_overlay: Control
var discovery_ui: Control

var biome_label := ""
var biome_kind := ""
var biome_temperature := 0.0
var biome_pressure := 0.0
var biome_gravity := 0.0

var is_debug := false
var is_catalogue_open := false

func _init() -> void:
	discovery = DiscoverySystem.new()
	chunk_map = {}
	sample_history = []

func init_planet(preset_name: String = "earthlike", seed_value: int = 12345) -> void:
	planet = PlanetParameters.from_preset(preset_name, seed_value)
	solver = CoupledPlanetSolver.new(planet, seed_value)
	discovery = DiscoverySystem.new()
	chunk_map = {}
	sample_history = []
	biome_label = ""
	biome_kind = ""

func get_chunk(cx: int, cy: int) -> Dictionary:
	var key := _chunk_key(cx, cy)
	if chunk_map.has(key):
		return chunk_map[key]
	return {}

func has_chunk(cx: int, cy: int) -> bool:
	return chunk_map.has(_chunk_key(cx, cy))

func load_chunk(cx: int, cy: int) -> Dictionary:
	var key := _chunk_key(cx, cy)
	if chunk_map.has(key):
		return chunk_map[key]
	var result := solver.generate_chunk(cx, cy)
	chunk_map[key] = result
	return result

func unload_chunk(cx: int, cy: int) -> void:
	chunk_map.erase(_chunk_key(cx, cy))

func unload_distant_chunks(player_cx: int, player_cy: int) -> void:
	var keys_to_remove: Array = []
	for k in chunk_map.keys():
		var parts: PackedStringArray = k.split("_")
		var cx := int(parts[0])
		var cy := int(parts[1])
		if abs(cx - player_cx) > CHUNK_LOAD_RADIUS or abs(cy - player_cy) > CHUNK_LOAD_RADIUS:
			keys_to_remove.append(k)
	for k in keys_to_remove:
		chunk_map.erase(k)

func take_sample(position: Vector2) -> Dictionary:
	var cx := int(floor(position.x / CoupledPlanetSolver.CHUNK_EDGE))
	var cy := int(floor(position.y / CoupledPlanetSolver.CHUNK_EDGE))
	var local_x := position.x - (cx * CoupledPlanetSolver.CHUNK_EDGE)
	var local_y := position.y - (cy * CoupledPlanetSolver.CHUNK_EDGE)
	var cell := _find_cell(cx, cy, local_x, local_y)
	if cell.is_empty():
		return {}
	var report := SampleReport.build(cell, planet, solver, position)
	sample_history.append(report)
	var result := discovery.process(report)
	biome_label = report.get("classification", "")
	biome_kind = report.get("kind", "")
	biome_temperature = report.get("temperature", 0.0)
	biome_pressure = report.get("pressure", 0.0)
	biome_gravity = report.get("gravity", 0.0)
	return {"report": report, "discovery": result}

func _find_cell(cx: int, cy: int, local_x: float, local_y: float) -> Dictionary:
	var chunk := get_chunk(cx, cy)
	var records: Array[Dictionary] = chunk.get("records", [])
	if records.is_empty():
		return {}
	var cell_size: float = chunk.get("cell_size", CoupledPlanetSolver.CELL_SIZE)
	var origin: Vector2 = chunk.get("origin", Vector2.ZERO)
	var closest: Dictionary = records[0]
	var closest_dist: float = INF
	for idx in records.size():
		var ix := idx % CoupledPlanetSolver.CHUNK_CELLS
		var iy := idx / CoupledPlanetSolver.CHUNK_CELLS
		var rx := origin.x + (ix + 0.5) * cell_size
		var ry := origin.y + (iy + 0.5) * cell_size
		var d := Vector2(rx - local_x, ry - local_y).length()
		if d < closest_dist:
			closest_dist = d
			closest = records[idx]
	return closest

static func _chunk_key(cx: int, cy: int) -> String:
	return "%d_%d" % [cx, cy]
