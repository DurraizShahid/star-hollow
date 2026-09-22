# hud.gd
# -----------------------------------------------------------------------------
# Bottom-left HUD: planet name, position, biome classification,
# temperature, pressure, gravity, sample count, discovery total.
# -----------------------------------------------------------------------------
class_name HUD
extends Control

@onready var _gs := get_node_or_null("/root/GameState") as GameState

var _label_refs: Array[Control] = []

func _ready() -> void:
	_setup_labels()
	set_process(true)

func _setup_labels() -> void:
	_label_refs.clear()
	var lines := [
		"planet: ",
		"pos: ",
		"biome: ",
		"temp: K",
		"press: Pa",
		"g: m/s2",
		"samples: ",
		"discovered: ",
	]
	for line in lines:
		var bb := Label.new()
		bb.text = line
		bb.custom_minimum_size = Vector2(200, 20)
		bb.add_theme_font_size_override("font_size", 13)
		add_child(bb)
		_label_refs.append(bb)
	set_position(Vector2(10, 20))

func _process(_delta: float) -> void:
	if _gs == null:
		return
	var p := _gs.planet
	if p == null:
		return
	var idx := 0
	_label_refs[idx].text = "planet: %s" % p.name; idx += 1
	var pos: Vector2 = _gs.player.global_position if _gs.player != null else Vector2.ZERO
	_label_refs[idx].text = "pos: %.0f, %.0f" % [pos.x, pos.y]; idx += 1
	_label_refs[idx].text = "biome: %s" % _gs.biome_label; idx += 1
	_label_refs[idx].text = "temp: %.1f K" % _gs.biome_temperature; idx += 1
	_label_refs[idx].text = "press: %.0f Pa" % _gs.biome_pressure; idx += 1
	_label_refs[idx].text = "g: %.2f m/s2" % _gs.biome_gravity; idx += 1
	_label_refs[idx].text = "samples: %d" % _gs.sample_history.size(); idx += 1
	var summary := _gs.discovery.summary()
	_label_refs[idx].text = "discovered: %d" % summary.total; idx += 1
