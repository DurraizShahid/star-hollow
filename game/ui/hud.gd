# hud.gd
class_name HUD
extends CanvasLayer

var _gs: GameState
var _panel: PanelContainer
var _label: RichTextLabel

func _ready() -> void:
	layer = 10
	_gs = get_node_or_null("/root/GameState") as GameState
	_panel = PanelContainer.new()
	_panel.position = Vector2(14, 14)
	_panel.custom_minimum_size = Vector2(350, 150)
	add_child(_panel)
	_label = RichTextLabel.new()
	_label.bbcode_enabled = true
	_label.fit_content = true
	_label.scroll_active = false
	_label.custom_minimum_size = Vector2(330, 140)
	_panel.add_child(_label)

func _process(_delta: float) -> void:
	if _gs == null or _gs.planet == null:
		return
	var p := _gs.planet
	var pos := _gs.player.global_position if _gs.player != null else Vector2.ZERO
	var summary := _gs.discovery.summary()
	_label.text = """[b]%s[/b]  [color=#94aabd]seed %d · gen v%d[/color]
Pos %.1f, %.1f m  |  Elev %.1f m
%s
Ground %.2f K / %.2f °C  |  Air %.2f K
Pressure %s Pa  |  g %.3f m/s²
Samples %d  |  Elements %d · Compounds %d · Materials %d
[color=#a7bac7]WASD move · X probe · Tab discoveries · F1 science overlay · F2 field[/color]""" % [
		p.name, p.seed, SciConstants.WORLD_GENERATOR_VERSION,
		pos.x, pos.y, _gs.current_elevation,
		_gs.current_label,
		_gs.current_temperature, SciConstants.k_to_c(_gs.current_temperature), _gs.current_air_temperature,
		String.num_scientific(_gs.current_pressure), _gs.current_gravity,
		_gs.sample_history.size(), summary.elements, summary.compounds, summary.materials
	]
