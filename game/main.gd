# main.gd
class_name Main
extends Node2D

const CHUNK_LOAD_RADIUS := 2
const CHUNKS_PER_FRAME := 1
const ChunkRendererScript := preload("res://game/world/procedural_chunk_renderer.gd")
const ProbePopupScript := preload("res://game/ui/probe_popup.gd")

var _player_cx := 999999
var _player_cy := 999999
var _gs: GameState
var _chunk_layer: Node2D
var _visual_chunks: Dictionary = {}
var _pending_chunks: Array = []

func _ready() -> void:
	_gs = get_node_or_null("/root/GameState") as GameState
	if _gs == null:
		push_error("GameState autoload not found")
		return

	_chunk_layer = Node2D.new()
	_chunk_layer.name = "ChunkLayer"
	add_child(_chunk_layer)
	_make_player()

	# Runtime planet changes (preset/random/load) invalidate generated visuals.
	_gs.planet_changed.connect(_on_planet_changed)
	_gs.debug_field_changed.connect(_on_debug_field_changed)
	_gs.init_planet("earthlike", 12345)

	var load_result := _gs.load_saved_game()
	if load_result.get("ok", false):
		print("Loaded Star Hollow save for generator v%d" % SciConstants.WORLD_GENERATOR_VERSION)
	elif load_result.get("reason", "") == "generator_version_mismatch":
		push_warning("Existing save uses generator v%d; current generator is v%d, so it was not loaded." % [
			load_result.get("saved_generator_version", -1), SciConstants.WORLD_GENERATOR_VERSION])

	_make_ui()
	_schedule_streaming(true)
	_service_streaming(1) # center chunk first so HUD/probe are immediately valid
	_gs.update_environment(_gs.player.global_position)

func _process(_delta: float) -> void:
	if _gs == null or _gs.player == null or _gs.solver == null:
		return
	var world_pos := _gs.player.global_position
	var cx := floori(world_pos.x / CoupledPlanetSolver.CHUNK_EDGE)
	var cy := floori(world_pos.y / CoupledPlanetSolver.CHUNK_EDGE)
	if cx != _player_cx or cy != _player_cy:
		_schedule_streaming(false)
	_service_streaming(CHUNKS_PER_FRAME)
	_gs.update_environment(world_pos)

func _unhandled_input(event: InputEvent) -> void:
	if _gs == null or not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	var code := key.physical_keycode if key.physical_keycode != 0 else key.keycode
	match code:
		KEY_F3:
			_cycle_validation_planet()
			get_viewport().set_input_as_handled()
		KEY_F4:
			_new_random_planet()
			get_viewport().set_input_as_handled()
		KEY_F5:
			if _gs.save_game():
				print("Star Hollow saved.")
			get_viewport().set_input_as_handled()
		KEY_F9:
			var loaded := _gs.load_saved_game()
			if loaded.get("ok", false):
				_schedule_streaming(true)
				_service_streaming(1)
				print("Star Hollow save loaded.")
			else:
				push_warning("Save load failed: %s" % loaded.get("reason", "unknown"))
			get_viewport().set_input_as_handled()

func _schedule_streaming(force: bool) -> void:
	if _gs.player == null or _gs.solver == null:
		return
	var pos := _gs.player.global_position
	var cx := floori(pos.x / CoupledPlanetSolver.CHUNK_EDGE)
	var cy := floori(pos.y / CoupledPlanetSolver.CHUNK_EDGE)
	if not force and cx == _player_cx and cy == _player_cy:
		return
	_player_cx = cx
	_player_cy = cy
	_pending_chunks.clear()

	# Center first, then concentric square rings. This avoids a 25-chunk startup
	# stall while preserving the same eventual 5x5 loaded neighborhood.
	for radius in range(CHUNK_LOAD_RADIUS + 1):
		for dx in range(-radius, radius + 1):
			for dy in range(-radius, radius + 1):
				if maxi(abs(dx), abs(dy)) != radius:
					continue
				var tcx := cx + dx
				var tcy := cy + dy
				var key := GameState._chunk_key(tcx, tcy)
				if not _visual_chunks.has(key):
					_pending_chunks.append(Vector2i(tcx, tcy))

	var removed := _gs.unload_distant_chunks(cx, cy)
	for key in removed:
		if _visual_chunks.has(key):
			var visual: Node = _visual_chunks[key]
			if is_instance_valid(visual):
				visual.queue_free()
			_visual_chunks.erase(key)

func _service_streaming(max_chunks: int) -> void:
	var generated := 0
	while generated < max_chunks and not _pending_chunks.is_empty():
		var coord: Vector2i = _pending_chunks.pop_front()
		var key := GameState._chunk_key(coord.x, coord.y)
		if _visual_chunks.has(key):
			continue
		var chunk := _gs.load_chunk(coord.x, coord.y)
		_create_chunk_visual(key, chunk)
		generated += 1

func _create_chunk_visual(key: String, chunk: Dictionary) -> void:
	var renderer := ChunkRendererScript.new()
	renderer.name = "chunk_%s" % key
	_chunk_layer.add_child(renderer)
	renderer.configure(chunk, _gs.planet.seed, _gs.debug_field)
	_visual_chunks[key] = renderer

func _clear_visual_chunks() -> void:
	_pending_chunks.clear()
	for key in _visual_chunks.keys():
		var visual: Node = _visual_chunks[key]
		if is_instance_valid(visual):
			visual.queue_free()
	_visual_chunks.clear()
	_player_cx = 999999
	_player_cy = 999999

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
	var popup := ProbePopupScript.new()
	popup.name = "ProbePopup"
	add_child(popup)
	_gs.sample_popup = popup

func _on_planet_changed() -> void:
	_clear_visual_chunks()
	if _gs.player != null:
		_gs.player.global_position = Vector2.ZERO

func _on_debug_field_changed(field: String) -> void:
	for key in _visual_chunks.keys():
		var renderer = _visual_chunks[key]
		if is_instance_valid(renderer):
			renderer.set_debug_field(field)

func _cycle_validation_planet() -> void:
	var presets := PlanetParameters.presets()
	var current := presets.find(_gs.planet.preset)
	var next_index := posmod(current + 1, presets.size()) if current >= 0 else 0
	_gs.init_planet(String(presets[next_index]), _gs.planet.seed)
	_schedule_streaming(true)
	_service_streaming(1)

func _new_random_planet() -> void:
	var next_seed := int(Time.get_unix_time_from_system()) & 0x7fffffff
	_gs.init_random_planet(next_seed)
	_schedule_streaming(true)
	_service_streaming(1)

func _exit_tree() -> void:
	if _gs != null and _gs.planet != null:
		_gs.save_game()
