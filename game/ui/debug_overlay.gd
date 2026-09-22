# debug_overlay.gd
# -----------------------------------------------------------------------------
# F1 toggle debug overlay: chunk map, solver convergence, FPS, memory.
# -----------------------------------------------------------------------------
class_name DebugOverlay
extends Control

@onready var _gs := get_node_or_null("/root/GameState") as GameState
var _visible := false
var _fps := 0
var _frame_count := 0
var _fps_timer := 0.0

func _ready() -> void:
	set_process(true)
	visible = false

func _input(event: InputEvent) -> void:
	if _gs != null and event.is_action_pressed("ui_cancel") and not _gs.is_catalogue_open:
		_visible = not _visible
		visible = _visible

func _process(_delta: float) -> void:
	if not visible:
		return
	_fps_timer += _delta
	_frame_count += 1
	if _fps_timer >= 0.5:
		_fps = roundi(_frame_count / _fps_timer)
		_frame_count = 0
		_fps_timer = 0.0
	queue_redraw()

func _draw() -> void:
	if _gs == null:
		return
	var lines := [
		"DEBUG OVERLAY (F1/Cancel to close)",
		"FPS: %d" % _fps,
		"Chunks loaded: %d" % _gs.chunk_map.size(),
		"Player pos: %.0f, %.0f" % [_gs.player.global_position.x, _gs.player.global_position.y],
		"Solver t_atm: %.1f K" % _gs.solver.t_atm,
		"World gen v: %d" % SciConstants.WORLD_GENERATOR_VERSION,
	]
	var y := 10
	for line in lines:
		draw_string(ThemeDB.fallback_font, Vector2(10, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0, 0, 0, 0.9))
		y += 18

func _toggle() -> void:
	_visible = not _visible
	visible = _visible
