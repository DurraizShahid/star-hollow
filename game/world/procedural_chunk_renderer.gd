# procedural_chunk_renderer.gd
# Runtime-only terrain renderer. No authored terrain tiles or biome atlas.
class_name ProceduralChunkRenderer
extends Node2D

const TEXTURE_SIZE := 64
const CELLS := CoupledPlanetSolver.CHUNK_CELLS

var chunk: Dictionary
var world_seed := 0
var debug_field := "normal"
var game_state: GameState
var ground_sprite: Sprite2D
var rock_instances: MultiMeshInstance2D
var plant_instances: MultiMeshInstance2D

func configure(chunk_data: Dictionary, seed_value: int, field: String = "normal", gs: GameState = null) -> void:
	chunk = chunk_data
	world_seed = seed_value
	debug_field = field
	game_state = gs
	position = chunk.get("origin", Vector2.ZERO)
	_rebuild()

func set_debug_field(field: String) -> void:
	if debug_field == field:
		return
	debug_field = field
	_rebuild_ground()

func _rebuild() -> void:
	for child in get_children():
		child.queue_free()
	ground_sprite = Sprite2D.new()
	ground_sprite.centered = false
	add_child(ground_sprite)
	_rebuild_ground()
	_build_rocks()
	_build_plants()

func _rebuild_ground() -> void:
	if chunk.is_empty():
		return
	var image := Image.create_empty(TEXTURE_SIZE, TEXTURE_SIZE, false, Image.FORMAT_RGBA8)
	for py in range(TEXTURE_SIZE):
		for px in range(TEXTURE_SIZE):
			var u := (float(px) + 0.5) / float(TEXTURE_SIZE)
			var v := (float(py) + 0.5) / float(TEXTURE_SIZE)
			var color := _interpolated_color(u, v)
			if debug_field == "normal":
				var world_x := position.x + u * CoupledPlanetSolver.CHUNK_EDGE
				var world_y := position.y + v * CoupledPlanetSolver.CHUNK_EDGE
				var micro := (_hash01(world_x * 3.1, world_y * 2.7, 41) - 0.5) * 0.10
				color = color.lightened(maxf(0.0, micro)).darkened(maxf(0.0, -micro))
			image.set_pixel(px, py, color)
	var texture := ImageTexture.create_from_image(image)
	ground_sprite.texture = texture
	ground_sprite.scale = Vector2(
		CoupledPlanetSolver.CHUNK_EDGE / float(TEXTURE_SIZE),
		CoupledPlanetSolver.CHUNK_EDGE / float(TEXTURE_SIZE)
	)
	ground_sprite.z_index = -10

func _interpolated_color(u: float, v: float) -> Color:
	# Interpolate in the GLOBAL cell lattice so a chunk edge uses the neighbor's
	# science cell rather than clamping to its own edge cell.
	var world_x := position.x + u * CoupledPlanetSolver.CHUNK_EDGE
	var world_y := position.y + v * CoupledPlanetSolver.CHUNK_EDGE
	var gx := world_x / CoupledPlanetSolver.CELL_SIZE - 0.5
	var gy := world_y / CoupledPlanetSolver.CELL_SIZE - 0.5
	var x0 := floori(gx)
	var y0 := floori(gy)
	var x1 := x0 + 1
	var y1 := y0 + 1
	var tx := gx - x0
	var ty := gy - y0
	var c00 := _cell_color(_record_global(x0, y0))
	var c10 := _cell_color(_record_global(x1, y0))
	var c01 := _cell_color(_record_global(x0, y1))
	var c11 := _cell_color(_record_global(x1, y1))
	return c00.lerp(c10, tx).lerp(c01.lerp(c11, tx), ty)

func _record_global(cell_x: int, cell_y: int) -> Dictionary:
	if game_state != null:
		var global_record := game_state.cell_at_grid(cell_x, cell_y, false)
		if not global_record.is_empty():
			return global_record
	# Fallback is only used at the outermost not-yet-loaded streaming edge.
	var origin_cell_x := floori(position.x / CoupledPlanetSolver.CELL_SIZE)
	var origin_cell_y := floori(position.y / CoupledPlanetSolver.CELL_SIZE)
	return _record(clampi(cell_x-origin_cell_x,0,CELLS-1), clampi(cell_y-origin_cell_y,0,CELLS-1))

func _record(ix: int, iy: int) -> Dictionary:
	var records: Array = chunk.get("records", [])
	var idx := iy * CELLS + ix
	return records[idx] if idx >= 0 and idx < records.size() else {}

func _cell_color(record: Dictionary) -> Color:
	if record.is_empty():
		return Color(0.1, 0.1, 0.1)
	if debug_field != "normal":
		return _debug_color(record, debug_field)
	var sub: SubstrateState = record["substrate"]
	var surf: SurfaceState = record["surface"]
	var thermal: ThermalState = record["thermal"]
	var base := _mineral_mix_color(sub)
	if surf.sediment_cover > 0.0:
		base = base.lerp(_sediment_color(surf.sediment_kind, sub), surf.sediment_cover * 0.75)
	if surf.salt_cover > 0.0:
		base = base.lerp(Color(0.88, 0.86, 0.79), surf.salt_cover)
	if surf.organic_cover > 0.0:
		base = base.lerp(Color(0.20, 0.13, 0.09), surf.organic_cover * 0.75)
	if surf.vegetation_cover > 0.0:
		base = base.lerp(Color(0.17, 0.30, 0.12), surf.vegetation_cover * 0.65)
	if surf.frost_cover > 0.0:
		base = base.lerp(_volatile_color(surf.frost_species, true), surf.frost_cover)
	if surf.liquid_cover > 0.0:
		base = base.lerp(_volatile_color(surf.liquid_species, false), surf.liquid_cover)
	if thermal.temperature > 900.0:
		var hot := clampf((thermal.temperature - 900.0) / 1800.0, 0.0, 1.0)
		base = base.lerp(Color(1.0, 0.22, 0.03), hot * 0.65)
	return base.clamp()

func _mineral_mix_color(sub: SubstrateState) -> Color:
	var mixed := Color(0.35, 0.34, 0.32)
	var total := 0.0
	for mineral in sub.bedrock_minerals:
		var f := float(mineral.get("fraction", 0.0))
		if f <= 0.0:
			continue
		var c := _mineral_color(String(mineral.get("name", "")))
		if total <= 0.0:
			mixed = c
			total = f
		else:
			var new_total := total + f
			mixed = mixed.lerp(c, f / new_total)
			total = new_total
	mixed = mixed.lerp(Color(0.46, 0.19, 0.10), sub.oxidation_index * 0.55)
	mixed = mixed.lerp(Color(0.47, 0.46, 0.41), sub.weathering_index * 0.25)
	return mixed

func _mineral_color(name: String) -> Color:
	if name.contains("Hematite"): return Color(0.46, 0.18, 0.11)
	if name.contains("Magnetite"): return Color(0.12, 0.13, 0.14)
	if name.contains("Graphite") or name.contains("Cementite"): return Color(0.13, 0.13, 0.14)
	if name.contains("Quartz"): return Color(0.74, 0.72, 0.69)
	if name.contains("Feldspar") or name.contains("Albite") or name.contains("Anorthite"): return Color(0.66, 0.61, 0.57)
	if name.contains("Olivine") or name.contains("Forsterite"): return Color(0.34, 0.38, 0.25)
	if name.contains("Pyroxene") or name.contains("Enstatite") or name.contains("Diopside"): return Color(0.26, 0.27, 0.23)
	if name.contains("Halite") or name.contains("Gypsum") or name.contains("Anhydrite"): return Color(0.84, 0.82, 0.77)
	if name.contains("Sulfur"): return Color(0.79, 0.66, 0.13)
	if name.contains("Pyrite"): return Color(0.56, 0.50, 0.26)
	if name.contains("Iron") or name.contains("Metal"): return Color(0.42, 0.43, 0.45)
	return Color(0.36, 0.35, 0.32)

func _sediment_color(kind: String, sub: SubstrateState) -> Color:
	var parent := _mineral_mix_color(sub)
	match kind:
		"clay": return parent.lerp(Color(0.47, 0.34, 0.25), 0.35)
		"silt": return parent.lightened(0.14)
		"sand": return parent.lightened(0.20)
		"dune": return parent.lightened(0.25)
		"gravel": return parent.darkened(0.08)
	return parent

func _volatile_color(species: String, solid: bool) -> Color:
	match species:
		"H2O": return Color(0.82, 0.92, 0.98) if solid else Color(0.08, 0.24, 0.43)
		"CH4": return Color(0.76, 0.84, 0.85) if solid else Color(0.12, 0.20, 0.22)
		"N2": return Color(0.88, 0.90, 0.93) if solid else Color(0.26, 0.34, 0.40)
		"CO2": return Color(0.91, 0.92, 0.94) if solid else Color(0.24, 0.27, 0.28)
		"NH3": return Color(0.88, 0.87, 0.82) if solid else Color(0.25, 0.30, 0.28)
		"CO": return Color(0.86, 0.89, 0.92) if solid else Color(0.25, 0.30, 0.34)
		"SO2": return Color(0.82, 0.80, 0.67) if solid else Color(0.44, 0.38, 0.20)
	return Color(0.75, 0.78, 0.80) if solid else Color(0.14, 0.24, 0.31)

func _debug_color(record: Dictionary, field: String) -> Color:
	var sub: SubstrateState = record["substrate"]
	var surf: SurfaceState = record["surface"]
	var thermal: ThermalState = record["thermal"]
	var atm: AtmosphereState = record["atmosphere"]
	var boundary: GeologyModel.CellBoundary = record["boundary"]
	var value := 0.0
	match field:
		"elevation": value = clampf(0.5 + boundary.elevation / 12000.0, 0.0, 1.0)
		"ground_temperature": value = clampf((thermal.temperature - 40.0) / 700.0, 0.0, 1.0)
		"air_temperature": value = clampf((atm.temperature - 40.0) / 700.0, 0.0, 1.0)
		"pressure": value = clampf(((log(maxf(atm.total_pressure, 1.0e-4)) / log(10.0)) + 4.0) / 11.0, 0.0, 1.0)
		"albedo": value = surf.albedo
		"density": value = clampf(sub.bulk_density / 6000.0, 0.0, 1.0)
		"water": value = maxf(surf.liquid_cover, surf.frost_cover)
		"dominant_mineral": return _category_color(sub.dominant_mineral())
		"iron": value = clampf(float(sub.elemental_mass_fraction.get("Fe", 0.0)) * 5.0, 0.0, 1.0)
		"carbon": value = clampf(float(sub.elemental_mass_fraction.get("C", 0.0)) * 8.0, 0.0, 1.0)
		"sulfur": value = clampf(float(sub.elemental_mass_fraction.get("S", 0.0)) * 12.0, 0.0, 1.0)
		"sediment": value = surf.sediment_cover
		"weathering": value = sub.weathering_index
		"vegetation_suitability": value = clampf(float(record.get("biosphere", {}).get("habitability", 0.0)), 0.0, 1.0)
		"wind": value = clampf(atm.wind_speed_m_s / 5.0, 0.0, 1.0)
		"province": return _category_color(boundary.province_primary)
		"coupling": return Color(0.15, 0.75, 0.25) if record.get("coupling", {}).get("converged", false) else Color(0.85, 0.16, 0.12)
		_: return _mineral_mix_color(sub)
	return _scientific_ramp(value)

func _category_color(label: String) -> Color:
	var h := abs(label.hash()) % 360
	return Color.from_hsv(float(h) / 360.0, 0.62, 0.88)

func _scientific_ramp(v: float) -> Color:
	v = clampf(v, 0.0, 1.0)
	if v < 0.25:
		return Color(0.08, 0.12, 0.42).lerp(Color(0.05, 0.62, 0.78), v / 0.25)
	if v < 0.50:
		return Color(0.05, 0.62, 0.78).lerp(Color(0.25, 0.78, 0.35), (v - 0.25) / 0.25)
	if v < 0.75:
		return Color(0.25, 0.78, 0.35).lerp(Color(0.95, 0.78, 0.12), (v - 0.50) / 0.25)
	return Color(0.95, 0.78, 0.12).lerp(Color(0.85, 0.12, 0.08), (v - 0.75) / 0.25)

func _build_rocks() -> void:
	var transforms: Array[Transform2D] = []
	var colors: Array[Color] = []
	for iy in range(CELLS):
		for ix in range(CELLS):
			var record := _record(ix, iy)
			if record.is_empty(): continue
			var surf: SurfaceState = record["surface"]
			var sub: SubstrateState = record["substrate"]
			var probability := clampf(0.08 + surf.rock_cover * 0.42 + surf.boulder_cover * 0.60, 0.0, 0.85)
			var x0 := (ix + 0.5) * CoupledPlanetSolver.CELL_SIZE
			var y0 := (iy + 0.5) * CoupledPlanetSolver.CELL_SIZE
			if _hash01(position.x + x0, position.y + y0, 71) > probability: continue
			var jitter := Vector2((_hash01(position.x+x0, position.y+y0, 72)-0.5)*6.0, (_hash01(position.x+x0, position.y+y0, 73)-0.5)*6.0)
			var size := lerpf(0.8, 3.6, _hash01(position.x+x0, position.y+y0, 74))
			var rot := _hash01(position.x+x0, position.y+y0, 75) * TAU
			transforms.append(Transform2D(rot, Vector2(size, size*0.68), 0.0, Vector2(x0,y0)+jitter))
			colors.append(_mineral_mix_color(sub).darkened(0.12))
	rock_instances = _make_multimesh(transforms, colors, false)
	rock_instances.z_index = 2
	add_child(rock_instances)

func _build_plants() -> void:
	var transforms: Array[Transform2D] = []
	var colors: Array[Color] = []
	for iy in range(CELLS):
		for ix in range(CELLS):
			var record := _record(ix, iy)
			if record.is_empty(): continue
			var surf: SurfaceState = record["surface"]
			if surf.vegetation_cover <= 0.01: continue
			var x0 := (ix + 0.5) * CoupledPlanetSolver.CELL_SIZE
			var y0 := (iy + 0.5) * CoupledPlanetSolver.CELL_SIZE
			if _hash01(position.x+x0, position.y+y0, 91) > surf.vegetation_cover: continue
			var jitter := Vector2((_hash01(position.x+x0, position.y+y0, 92)-0.5)*5.0, (_hash01(position.x+x0, position.y+y0, 93)-0.5)*5.0)
			var size := lerpf(0.8, 2.2, _hash01(position.x+x0, position.y+y0, 94))
			transforms.append(Transform2D(0.0, Vector2(size*0.55,size), 0.0, Vector2(x0,y0)+jitter))
			colors.append(Color(0.15,0.32,0.12).lightened(_hash01(position.x+x0, position.y+y0, 95)*0.12))
	plant_instances = _make_multimesh(transforms, colors, true)
	plant_instances.z_index = 3
	add_child(plant_instances)

func _make_multimesh(transforms: Array[Transform2D], colors: Array[Color], plant: bool) -> MultiMeshInstance2D:
	var node := MultiMeshInstance2D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true
	mm.instance_count = transforms.size()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(1.8, 2.8 if plant else 1.8)
	mm.mesh = mesh
	for i in range(transforms.size()):
		mm.set_instance_transform_2d(i, transforms[i])
		mm.set_instance_color(i, colors[i])
	node.multimesh = mm
	node.material = _shape_material(plant)
	return node

func _shape_material(plant: bool) -> ShaderMaterial:
	var shader := Shader.new()
	var distance_expr := "max(abs(p.x) * 1.8, length(p - vec2(0.0, -0.2)) * 0.82)" if plant else "dot(p, p)"
	shader.code = """shader_type canvas_item;
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = %s;
	if (d > 1.0) discard;
	vec4 c = COLOR;
	float edge = 1.0 - smoothstep(0.70, 1.0, d);
	COLOR = vec4(c.rgb * (0.78 + 0.22 * edge), c.a);
}""" % distance_expr
	var mat := ShaderMaterial.new()
	mat.shader = shader
	return mat

func _hash01(x: float, y: float, salt: int) -> float:
	var xi := floori(x * 17.0)
	var yi := floori(y * 19.0)
	var n := xi * 374761393 + yi * 668265263 + world_seed * 69069 + salt * 362437
	n = (n ^ (n >> 13)) * 1274126177
	n = n ^ (n >> 16)
	return float(n & 0x7fffffff) / 2147483647.0
