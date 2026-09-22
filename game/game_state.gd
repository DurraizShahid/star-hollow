# game_state.gd
class_name GameState
extends Node

const SaveSystemScript := preload("res://game/save_system.gd")

signal debug_field_changed(field: String)
signal planet_changed()
signal sample_taken(result: Dictionary)

const CHUNK_LOAD_RADIUS := 2
const DEBUG_FIELDS := [
	"normal", "elevation", "ground_temperature", "air_temperature", "pressure",
	"albedo", "density", "water", "dominant_mineral", "iron", "carbon", "sulfur",
	"sediment", "weathering", "vegetation_suitability", "wind", "province", "coupling"
]

var planet: PlanetParameters
var solver: CoupledPlanetSolver
var discovery: DiscoverySystem
var chunk_map: Dictionary = {}
var sample_history: Array = []

var player: Node2D
var hud: Node
var debug_overlay: Node
var discovery_ui: Node
var sample_popup: Node

var current_label := ""
var current_kind := ""
var current_temperature := 0.0
var current_air_temperature := 0.0
var current_pressure := 0.0
var current_gravity := 0.0
var current_elevation := 0.0
var last_sample_result: Dictionary = {}

var is_debug := false
var is_catalogue_open := false
var is_probe_open := false
var debug_field := "normal"

func _init() -> void:
	discovery = DiscoverySystem.new()

func init_planet(preset_name: String = "earthlike", seed_value: int = 12345) -> void:
	planet = PlanetParameters.from_preset(preset_name, seed_value)
	solver = CoupledPlanetSolver.new(planet, seed_value)
	discovery = DiscoverySystem.new()
	chunk_map.clear()
	sample_history.clear()
	last_sample_result = {}
	current_label = ""
	current_kind = ""
	current_temperature = 0.0
	current_air_temperature = 0.0
	current_pressure = 0.0
	current_gravity = planet.surface_gravity
	current_elevation = 0.0
	is_probe_open = false
	planet_changed.emit()

func init_random_planet(seed_value: int) -> void:
	planet = PlanetParameters.from_random(seed_value)
	solver = CoupledPlanetSolver.new(planet, seed_value)
	discovery = DiscoverySystem.new()
	chunk_map.clear()
	sample_history.clear()
	last_sample_result = {}
	planet_changed.emit()

func get_chunk(cx: int, cy: int) -> Dictionary:
	return chunk_map.get(_chunk_key(cx, cy), {})

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

func unload_distant_chunks(player_cx: int, player_cy: int) -> Array[String]:
	var removed: Array[String] = []
	for key in chunk_map.keys():
		var coords := _parse_chunk_key(String(key))
		if abs(coords.x - player_cx) > CHUNK_LOAD_RADIUS or abs(coords.y - player_cy) > CHUNK_LOAD_RADIUS:
			removed.append(String(key))
	for key in removed:
		chunk_map.erase(key)
	return removed

func cell_at_grid(cell_x: int, cell_y: int, load_if_missing: bool = true) -> Dictionary:
	var cx := floori(float(cell_x) / float(CoupledPlanetSolver.CHUNK_CELLS))
	var cy := floori(float(cell_y) / float(CoupledPlanetSolver.CHUNK_CELLS))
	var chunk := get_chunk(cx, cy)
	if chunk.is_empty() and load_if_missing:
		chunk = load_chunk(cx, cy)
	if chunk.is_empty():
		return {}
	var ix := posmod(cell_x, CoupledPlanetSolver.CHUNK_CELLS)
	var iy := posmod(cell_y, CoupledPlanetSolver.CHUNK_CELLS)
	var records: Array = chunk.get("records", [])
	var index := iy * CoupledPlanetSolver.CHUNK_CELLS + ix
	return records[index] if index >= 0 and index < records.size() else {}

func cell_at_world(position: Vector2, load_if_missing: bool = true) -> Dictionary:
	if solver == null:
		return {}
	var cx := floori(position.x / CoupledPlanetSolver.CHUNK_EDGE)
	var cy := floori(position.y / CoupledPlanetSolver.CHUNK_EDGE)
	var chunk := get_chunk(cx, cy)
	if chunk.is_empty() and load_if_missing:
		chunk = load_chunk(cx, cy)
	if chunk.is_empty():
		return {}

	var origin: Vector2 = chunk.get("origin", CoupledPlanetSolver.chunk_origin(cx, cy))
	var local := position - origin
	var ix := clampi(floori(local.x / CoupledPlanetSolver.CELL_SIZE), 0, CoupledPlanetSolver.CHUNK_CELLS - 1)
	var iy := clampi(floori(local.y / CoupledPlanetSolver.CELL_SIZE), 0, CoupledPlanetSolver.CHUNK_CELLS - 1)
	var index := iy * CoupledPlanetSolver.CHUNK_CELLS + ix
	var records: Array = chunk.get("records", [])
	if index < 0 or index >= records.size():
		return {}
	return records[index]

func update_environment(position: Vector2) -> void:
	var cell := cell_at_world(position, false)
	if cell.is_empty():
		return
	var thermal: ThermalState = cell["thermal"]
	var atm: AtmosphereState = cell["atmosphere"]
	var boundary: GeologyModel.CellBoundary = cell["boundary"]
	current_label = cell.get("classification", {}).get("label", "")
	current_kind = cell.get("classification", {}).get("kind", "")
	current_temperature = thermal.temperature
	current_air_temperature = atm.temperature
	current_pressure = atm.total_pressure
	current_gravity = planet.surface_gravity
	current_elevation = boundary.elevation

func take_sample(position: Vector2) -> Dictionary:
	var cell := cell_at_world(position, true)
	if cell.is_empty():
		return {}
	var report := SampleReport.build(cell, planet, solver, position)
	var discovery_result := discovery.process(report)
	var result := {"report": report, "discovery": discovery_result}
	sample_history.append(report)
	last_sample_result = result
	update_environment(position)
	sample_taken.emit(result)
	# A probe discovery is a natural autosave boundary. Chunks remain deterministic and are not serialized.
	save_game()
	return result

func set_debug_field(field: String) -> void:
	if not DEBUG_FIELDS.has(field):
		return
	if debug_field == field:
		return
	debug_field = field
	debug_field_changed.emit(field)

func cycle_debug_field(step: int = 1) -> void:
	var idx := DEBUG_FIELDS.find(debug_field)
	if idx < 0:
		idx = 0
	idx = posmod(idx + step, DEBUG_FIELDS.size())
	set_debug_field(DEBUG_FIELDS[idx])

func debug_value_for_cell(cell: Dictionary, field: String = "") -> float:
	var f := debug_field if field == "" else field
	var thermal: ThermalState = cell.get("thermal")
	var atm: AtmosphereState = cell.get("atmosphere")
	var sub: SubstrateState = cell.get("substrate")
	var surf: SurfaceState = cell.get("surface")
	var boundary: GeologyModel.CellBoundary = cell.get("boundary")
	match f:
		"elevation": return boundary.elevation
		"ground_temperature": return thermal.temperature
		"air_temperature": return atm.temperature
		"pressure": return log(maxf(atm.total_pressure, SciConstants.MIN_PRESSURE_PA))
		"albedo": return surf.albedo
		"density": return sub.bulk_density
		"water": return maxf(surf.liquid_cover, surf.frost_cover)
		"dominant_mineral": return 1.0
		"iron": return float(sub.elemental_mass_fraction.get("Fe", 0.0))
		"carbon": return float(sub.elemental_mass_fraction.get("C", 0.0))
		"sulfur": return float(sub.elemental_mass_fraction.get("S", 0.0))
		"sediment": return surf.sediment_cover
		"weathering": return sub.weathering_index
		"vegetation_suitability": return float(cell.get("biosphere", {}).get("habitability", 0.0))
		"wind": return atm.wind_speed_m_s
		"province": return 1.0
		"coupling": return 1.0 if cell.get("coupling", {}).get("converged", false) else 0.0
	return 0.0

static func _chunk_key(cx: int, cy: int) -> String:
	return "%d_%d" % [cx, cy]

static func _parse_chunk_key(key: String) -> Vector2i:
	var parts := key.split("_")
	if parts.size() != 2:
		return Vector2i.ZERO
	return Vector2i(int(parts[0]), int(parts[1]))


func save_game(path: String = SaveSystemScript.DEFAULT_PATH) -> bool:
	return SaveSystemScript.save_game(self, path)

func load_saved_game(path: String = SaveSystemScript.DEFAULT_PATH) -> Dictionary:
	return SaveSystemScript.load_game(self, path)
