# main.gd
# -----------------------------------------------------------------------------
# Top-level game scene. Instantiates player, camera, chunk layer, HUD,
# debug overlay, and discovery UI. Handles chunk streaming.
# -----------------------------------------------------------------------------
class_name Main
extends Node2D

const CHUNK_LOAD_RADIUS := 2

var _player_cx := 0
var _player_cy := 0
var _gs: GameState = null

var _chunk_layer: Node2D = null

func _ready() -> void:
	_gs = get_node_or_null("/root/GameState") as GameState
	if _gs == null:
		push_error("GameState autoload not found")
		return
	_gs.hud = null
	_gs.debug_overlay = null
	_gs.discovery_ui = null
	_gs.init_planet("earthlike", 12345)
	_make_player()
	_make_ui()
	_chunk_layer = Node2D.new()
	_chunk_layer.name = "ChunkLayer"
	add_child(_chunk_layer)
	stream_chunks()

func _process(_delta: float) -> void:
	if _gs == null or _gs.player == null:
		return
	var world_pos: Vector2 = _gs.player.global_position
	var cx := int(floor(world_pos.x / CoupledPlanetSolver.CHUNK_EDGE))
	var cy := int(floor(world_pos.y / CoupledPlanetSolver.CHUNK_EDGE))
	if cx != _player_cx or cy != _player_cy:
		_player_cx = cx
		_player_cy = cy
		stream_chunks()
		_gs.unload_distant_chunks(cx, cy)

func stream_chunks() -> void:
	if _gs == null or _gs.player == null:
		return
	var cx := int(floor(_gs.player.global_position.x / CoupledPlanetSolver.CHUNK_EDGE))
	var cy := int(floor(_gs.player.global_position.y / CoupledPlanetSolver.CHUNK_EDGE))
	for dcx in range(-CHUNK_LOAD_RADIUS, CHUNK_LOAD_RADIUS + 1):
		for dcy in range(-CHUNK_LOAD_RADIUS, CHUNK_LOAD_RADIUS + 1):
			var tcx := cx + dcx
			var tcy := cy + dcy
			if not _gs.has_chunk(tcx, tcy):
				var chunk := _gs.load_chunk(tcx, tcy)
				if not chunk.is_empty():
					_make_chunk_visuals(tcx, tcy, chunk)

func _make_player() -> void:
	var player := PlayerController.new()
	player.name = "Player"
	player.game_state = _gs
	var cam := Camera2D.new()
	cam.name = "Camera2D"
	player.add_child(cam)
	var probe := Area2D.new()
	probe.name = "ProbeArea"
	probe.monitoring = true
	probe.body_entered.connect(func(_b): pass)
	probe.position = Vector2(0, -20)
	player.add_child(probe)
	var cs := CollisionShape2D.new()
	cs.shape = CircleShape2D.new()
	cs.shape.radius = 5.0
	probe.add_child(cs)
	add_child(player)
	cam.make_current()
	_gs.player = player

func _make_ui() -> void:
	if _gs == null:
		return
	var hud := HUD.new()
	hud.name = "HUD"
	_gs.hud = hud
	add_child(hud)
	var dbg := DebugOverlay.new()
	dbg.name = "DebugOverlay"
	_gs.debug_overlay = dbg
	add_child(dbg)
	var cat := DiscoveryCatalogue.new()
	cat.name = "DiscoveryUI"
	_gs.discovery_ui = cat
	add_child(cat)

func _make_chunk_visuals(cx: int, cy: int, chunk: Dictionary) -> void:
	if _gs == null or _gs.player == null:
		return
	var origin: Vector2 = chunk.get("origin", Vector2.ZERO)
	var records: Array = chunk.get("records", [])
	var cell_size: float = chunk.get("cell_size", CoupledPlanetSolver.CELL_SIZE)
	var mm := MultiMeshInstance2D.new()
	mm.multimesh = MultiMesh.new()
	mm.multimesh.use_colors = true
	mm.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	mm.multimesh.instance_count = records.size()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(cell_size * 0.95, cell_size * 0.95)
	mm.multimesh.mesh = mesh
	var ccx := int(floor(_gs.player.global_position.x / CoupledPlanetSolver.CHUNK_EDGE))
	var ccy := int(floor(_gs.player.global_position.y / CoupledPlanetSolver.CHUNK_EDGE))
	for idx in records.size():
		var ix := idx % CoupledPlanetSolver.CHUNK_CELLS
		var iy := idx / CoupledPlanetSolver.CHUNK_CELLS
		var rec: Dictionary = records[idx]
		var classif: Dictionary = rec.get("classification", {})
		var label: String = classif.get("label", "bare_rock")
		var color := _classification_color(label)
		var x := origin.x + (ix + 0.5) * cell_size
		var y := origin.y + (iy + 0.5) * cell_size
		var transform := Transform3D().translated(Vector3(x, y, 0))
		mm.multimesh.set_instance_transform(idx, transform)
		mm.multimesh.set_instance_color(idx, color)
	mm.name = "chunk_%d_%d" % [cx, cy]
	_chunk_layer.add_child(mm)

func _classification_color(label: String) -> Color:
	match label:
		"Ocean of H2O": return Color(0.15, 0.35, 0.85)
		"H2O frost plain": return Color(0.8, 0.9, 1.0)
		"CO2 frost plain": return Color(0.6, 0.7, 0.8)
		"aeolian dune field": return Color(0.85, 0.75, 0.5)
		"sandy plain": return Color(0.9, 0.85, 0.7)
		"clay mudflat": return Color(0.65, 0.55, 0.4)
		"tholin plain": return Color(0.35, 0.45, 0.3)
		_: return Color(0.4, 0.4, 0.4)
