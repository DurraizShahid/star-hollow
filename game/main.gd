# main.gd
class_name Main
extends Node2D

const CHUNK_LOAD_RADIUS := 2

var _player_cx := 999999
var _player_cy := 999999
var _gs: GameState
var _chunk_layer: Node2D
var _visual_chunks: Dictionary = {}

func _ready() -> void:
	_gs = get_node_or_null("/root/GameState") as GameState
	if _gs == null:
		push_error("GameState autoload not found")
		return
	_gs.init_planet("earthlike", 12345)
	_chunk_layer = Node2D.new()
	_chunk_layer.name = "ChunkLayer"
	add_child(_chunk_layer)
	_make_player()
	_make_ui()
	_gs.debug_field_changed.connect(_on_debug_field_changed)
	_update_streaming(true)
	_gs.update_environment(_gs.player.global_position)

func _process(_delta: float) -> void:
	if _gs == null or _gs.player == null:
		return
	var world_pos := _gs.player.global_position
	_gs.update_environment(world_pos)
	var cx := floori(world_pos.x / CoupledPlanetSolver.CHUNK_EDGE)
	var cy := floori(world_pos.y / CoupledPlanetSolver.CHUNK_EDGE)
	if cx != _player_cx or cy != _player_cy:
		_update_streaming(false)

func _update_streaming(force: bool) -> void:
	var world_pos := _gs.player.global_position
	var cx := floori(world_pos.x / CoupledPlanetSolver.CHUNK_EDGE)
	var cy := floori(world_pos.y / CoupledPlanetSolver.CHUNK_EDGE)
	if not force and cx == _player_cx and cy == _player_cy:
		return
	_player_cx = cx
	_player_cy = cy
	for dcx in range(-CHUNK_LOAD_RADIUS, CHUNK_LOAD_RADIUS + 1):
		for dcy in range(-CHUNK_LOAD_RADIUS, CHUNK_LOAD_RADIUS + 1):
			var tcx := cx + dcx
			var tcy := cy + dcy
			var key := GameState._chunk_key(tcx, tcy)
			var chunk := _gs.load_chunk(tcx, tcy)
			if not _visual_chunks.has(key):
				_create_chunk_visual(key, chunk)
	var removed := _gs.unload_distant_chunks(cx, cy)
	for key in removed:
		if _visual_chunks.has(key):
			var visual: Node = _visual_chunks[key]
			if is_instance_valid(visual):
				visual.queue_free()
			_visual_chunks.erase(key)

func _create_chunk_visual(key: String, chunk: Dictionary) -> void:
	var renderer := ProceduralChunkRenderer.new()
	renderer.name = "chunk_%s" % key
	_chunk_layer.add_child(renderer)
	renderer.configure(chunk, _gs.planet.seed, _gs.debug_field)
	_visual_chunks[key] = renderer

func _make_player() -> void:
	var player := PlayerController.new()
	player.name = "Player"
	player.game_state = _gs
	player.z_index = 20
	var cam := Camera2D.new()
	cam.name = "Camera2D"
	cam.position_smoothing_enabled = true
	cam.position_smoothing_speed = 8.0
	player.add_child(cam)
	add_child(player)
	cam.make_current()
	_gs.player = player

func _make_ui() -> void:
	var hud := HUD.new()
	hud.name = "HUD"
	add_child(hud)
	_gs.hud = hud
	var dbg := DebugOverlay.new()
	dbg.name = "DebugOverlay"
	add_child(dbg)
	_gs.debug_overlay = dbg
	var cat := DiscoveryCatalogue.new()
	cat.name = "DiscoveryUI"
	add_child(cat)
	_gs.discovery_ui = cat
	var popup := ProbePopup.new()
	popup.name = "ProbePopup"
	add_child(popup)
	_gs.sample_popup = popup

func _on_debug_field_changed(field: String) -> void:
	for key in _visual_chunks.keys():
		var renderer: ProceduralChunkRenderer = _visual_chunks[key]
		if is_instance_valid(renderer):
			renderer.set_debug_field(field)
