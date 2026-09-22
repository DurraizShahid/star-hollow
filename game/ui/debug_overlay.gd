# debug_overlay.gd
class_name DebugOverlay
extends CanvasLayer

var _gs: GameState
var _panel: PanelContainer
var _label: RichTextLabel
var _fps := 0.0

func _ready() -> void:
	layer = 20
	_gs = get_node_or_null("/root/GameState") as GameState
	_panel = PanelContainer.new()
	_panel.position = Vector2(14, 180)
	_panel.custom_minimum_size = Vector2(360, 200)
	add_child(_panel)
	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.custom_minimum_size = Vector2(340, 180)
	_panel.add_child(_label)
	visible = false

func _unhandled_input(event: InputEvent) -> void:
	if _gs == null or not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	var code := key.physical_keycode if key.physical_keycode != 0 else key.keycode
	if code == KEY_F1:
		visible = not visible
		_gs.is_debug = visible
		if not visible:
			_gs.set_debug_field("normal")
		elif _gs.debug_field == "normal":
			_gs.set_debug_field("ground_temperature")
		get_viewport().set_input_as_handled()
	elif code == KEY_F2 and visible:
		_gs.cycle_debug_field(1)
		get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if not visible or _gs == null:
		return
	_fps = Engine.get_frames_per_second()
	var cell := _gs.cell_at_world(_gs.player.global_position, false) if _gs.player != null else {}
	var residual := 0.0
	var coupling := {}
	var province := ""
	if not cell.is_empty():
		residual = float(cell.get("thermal").residual_w_m2)
		coupling = cell.get("coupling", {})
		province = cell.get("boundary").province_primary
	_label.text = """[b]SCIENCE DEBUG[/b]
Field: [b]%s[/b]  (F2 cycles)
FPS %.0f  |  science chunks %d
Province: %s
Cell residual: %.5e W/m²
Coupling: %s · %d iterations
Reference atmosphere T: %.2f K
Generator v%d
[color=#a7bac7]F1 closes and restores normal material rendering[/color]""" % [
		_gs.debug_field, _fps, _gs.chunk_map.size(), province, residual,
		"converged" if coupling.get("converged", false) else "approximate",
		int(coupling.get("iterations", 0)), _gs.solver.t_atm,
		SciConstants.WORLD_GENERATOR_VERSION
	]
