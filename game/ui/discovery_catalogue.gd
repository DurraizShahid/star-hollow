# discovery_catalogue.gd
class_name DiscoveryCatalogue
extends CanvasLayer

var _gs: GameState
var _root: Control
var _panel: PanelContainer
var _text: RichTextLabel

func _ready() -> void:
	layer = 25
	_gs = get_node_or_null("/root/GameState") as GameState
	_build_ui()
	visible = false

func _unhandled_input(event: InputEvent) -> void:
	if _gs == null or not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	var code := key.physical_keycode if key.physical_keycode != 0 else key.keycode
	if code == KEY_TAB and not _gs.is_probe_open:
		visible = not visible
		_gs.is_catalogue_open = visible
		if visible:
			_refresh()
		get_viewport().set_input_as_handled()
	elif code == KEY_ESCAPE and visible:
		visible = false
		_gs.is_catalogue_open = false
		get_viewport().set_input_as_handled()

func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)
	_panel = PanelContainer.new()
	_panel.anchor_left = 0.12
	_panel.anchor_top = 0.08
	_panel.anchor_right = 0.88
	_panel.anchor_bottom = 0.92
	_root.add_child(_panel)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.scroll_active = true
	_panel.add_child(_text)

func _refresh() -> void:
	var summary := _gs.discovery.summary()
	var lines: Array[String] = []
	lines.append("[font_size=24][b]DISCOVERY CATALOGUE[/b][/font_size]")
	lines.append("[color=#9eb7c9]Tab / Esc to close[/color]\n")
	lines.append("Elements: %d   Compounds: %d   Distinct material signatures: %d" % [
		summary.elements, summary.compounds, summary.materials
	])
	lines.append("Material novelty threshold: %.3f\n" % float(summary.novelty_threshold))
	lines.append("[b]ELEMENTS[/b]")
	for k in _gs.discovery.catalogue["elements"].keys():
		lines.append("%s  ×%d" % [k, _gs.discovery.catalogue["elements"][k]])
	lines.append("\n[b]COMPOUNDS / MINERALS[/b]")
	for k in _gs.discovery.catalogue["compounds"].keys():
		lines.append("%s  ×%d" % [k, _gs.discovery.catalogue["compounds"][k]])
	lines.append("\n[b]MATERIAL SIGNATURES[/b]")
	for rec in _gs.discovery.material_records:
		var pos: Vector2 = rec.get("first_position", Vector2.ZERO)
		lines.append("[b]%s[/b] — %s  ×%d   first %.0f, %.0f m" % [
			rec.get("id",""), rec.get("label",""), int(rec.get("count",0)), pos.x, pos.y
		])
	_text.text = "\n".join(lines)
