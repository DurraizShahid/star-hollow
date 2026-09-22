# discovery_catalogue.gd
# -----------------------------------------------------------------------------
# E toggle discovery catalogue. Lists all discovered elements,
# compounds, materials with counts and fingerprint distance.
# -----------------------------------------------------------------------------
class_name DiscoveryCatalogue
extends Control

@onready var _gs := get_node_or_null("/root/GameState") as GameState
var _visible := false

func _ready() -> void:
	set_process(true)
	visible = false

func _input(event: InputEvent) -> void:
	if _gs != null and event.is_action_pressed("ui_focus_next") and not _gs.is_debug:
		_visible = not _visible
		visible = _visible

func _process(_delta: float) -> void:
	if not visible:
		return
	queue_redraw()

func _draw() -> void:
	if _gs == null:
		return
	var summary := _gs.discovery.summary()
	var lines := [
		"DISCOVERY CATALOGUE (Tab to close)",
		"",
		"Elements: %d | Compounds: %d | Materials: %d | Total: %d" % [
			summary.elements, summary.compounds, summary.materials, summary.total,
		],
		"Farthest distance: %.3f" % summary.farthest_distance,
		"",
		"-- Elements --",
	]
	var y := 10
	for k in _gs.discovery.catalogue["elements"].keys():
		lines.append("  %s (x%d)" % [k, _gs.discovery.catalogue["elements"][k]])
	lines.append("")
	lines.append("-- Compounds --")
	for k in _gs.discovery.catalogue["compounds"].keys():
		lines.append("  %s (x%d)" % [k, _gs.discovery.catalogue["compounds"][k]])
	lines.append("")
	lines.append("-- Materials --")
	for k in _gs.discovery.catalogue["materials"].keys():
		lines.append("  %s (x%d)" % [k, _gs.discovery.catalogue["materials"][k]])
	for line in lines:
		draw_string(ThemeDB.fallback_font, Vector2(10, y), line, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0, 0, 0, 0.9))
		y += 16
	draw_rect(Rect2(Vector2.ZERO, Vector2(400, y + 10)), Color(0.95, 0.95, 0.95, 0.95), true)
	draw_rect(Rect2(Vector2.ZERO, Vector2(400, y + 10)), Color(0.3, 0.3, 0.3, 1.0), false)

func _toggle() -> void:
	_visible = not _visible
	visible = _visible
