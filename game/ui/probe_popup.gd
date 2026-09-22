# probe_popup.gd
class_name ProbePopup
extends CanvasLayer

var game_state: GameState
var root: Control
var panel: PanelContainer
var report_text: RichTextLabel

func _ready() -> void:
	layer = 30
	game_state = get_node_or_null("/root/GameState") as GameState
	_build_ui()
	visible = false

func _unhandled_input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if key.pressed and not key.echo and (key.physical_keycode in [KEY_ESCAPE, KEY_X] or key.keycode in [KEY_ESCAPE, KEY_X]):
		hide_probe()
		get_viewport().set_input_as_handled()

func show_result(result: Dictionary) -> void:
	report_text.text = _format_report(result)
	visible = true
	if game_state != null:
		game_state.is_probe_open = true

func hide_probe() -> void:
	visible = false
	if game_state != null:
		game_state.is_probe_open = false

func _build_ui() -> void:
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.04, 0.58)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(dim)
	panel = PanelContainer.new()
	panel.anchor_left = 0.08
	panel.anchor_top = 0.06
	panel.anchor_right = 0.92
	panel.anchor_bottom = 0.94
	root.add_child(panel)
	report_text = RichTextLabel.new()
	report_text.bbcode_enabled = true
	report_text.fit_content = false
	report_text.scroll_active = true
	report_text.custom_minimum_size = Vector2(640, 520)
	report_text.add_theme_font_size_override("normal_font_size", 15)
	panel.add_child(report_text)

func _format_report(result: Dictionary) -> String:
	var r: Dictionary = result.get("report", {})
	var d: Dictionary = result.get("discovery", {})
	var sub: Dictionary = r.get("substrate", {})
	var surf: Dictionary = r.get("surface", {})
	var atm: Dictionary = r.get("atmosphere", {})
	var model: Dictionary = r.get("model", {})
	var lines: Array[String] = []
	lines.append("[font_size=24][b]SAMPLE PROBE[/b][/font_size]")
	lines.append("[color=#9eb7c9]X / Esc to close[/color]\n")
	lines.append("[font_size=20][b]%s[/b][/font_size]" % r.get("classification", "Unclassified material"))
	lines.append("Material signature: [b]%s[/b]   New material: %s   Novelty distance: %.4f" % [
		d.get("material_signature", "—"), "YES" if d.get("material_new", false) else "no",
		float(d.get("novelty_distance", 0.0))
	])
	var p: Vector2 = r.get("position", Vector2.ZERO)
	lines.append("Coordinates: %.2f, %.2f m   Elevation: %.1f m   Gravity: %.3f m/s²" % [
		p.x, p.y, float(r.get("elevation_m", 0.0)), float(r.get("gravity", 0.0))
	])
	lines.append("\n[b]THERMAL / ENVIRONMENT[/b]")
	lines.append("Ground: %.2f K (%.2f °C)   Air: %.2f K   Shallow subsurface: %.2f K" % [
		float(r.get("temperature", 0.0)), SciConstants.k_to_c(float(r.get("temperature", 0.0))),
		float(r.get("air_temperature", 0.0)), float(r.get("shallow_subsurface_temperature", 0.0))
	])
	lines.append("Pressure: %s Pa   Air density: %.5g kg/m³" % [
		String.num_scientific(float(r.get("pressure", 0.0))), float(r.get("density", 0.0))
	])
	var phases: Dictionary = r.get("phase_fractions", {})
	lines.append("Surface phase cover — solid %.1f%% | liquid %.1f%% | frost/ice %.1f%%" % [
		100.0*float(phases.get("solid",0.0)), 100.0*float(phases.get("liquid",0.0)), 100.0*float(phases.get("frost_or_ice",0.0))
	])

	lines.append("\n[b]ELEMENTAL COMPOSITION — MASS % / MOLE %[/b]")
	var mass: Dictionary = r.get("elements_mass_pct", {})
	var mole: Dictionary = r.get("elements_mole_pct", {})
	for e in _sorted_keys_by_value(mass).slice(0, mini(16, mass.size())):
		lines.append("%-3s  %8.4f%% mass   %8.4f%% mole" % [e, float(mass[e]), float(mole.get(e, 0.0))])

	lines.append("\n[b]MINERAL / COMPOUND ASSEMBLAGE[/b]")
	for m in sub.get("minerals", []).slice(0, mini(12, sub.get("minerals", []).size())):
		lines.append("%-34s %8.3f%%" % [m.get("name","?"), float(m.get("mass_pct",0.0))])

	lines.append("\n[b]GROUND PHYSICAL PROPERTIES[/b]")
	lines.append("Regolith: %.3f m   Porosity: %.3f   Grain mean: %.4g m   Grain spread σg: %.2f" % [
		float(sub.get("regolith_m",0.0)), float(sub.get("porosity",0.0)),
		float(sub.get("grain_size_mean_m",0.0)), float(sub.get("grain_size_sigma",0.0))
	])
	lines.append("Grain density: %.1f kg/m³   Bulk density: %.1f kg/m³   Permeability: %.3g m²" % [
		float(sub.get("grain_density_kg_m3",0.0)), float(sub.get("bulk_density_kg_m3",0.0)),
		float(sub.get("permeability_m2",0.0))
	])
	lines.append("k: %.3f W/(m·K)   cp: %.1f J/(kg·K)   diffusivity: %.3g m²/s   hardness ≈ %.2f Mohs" % [
		float(sub.get("thermal_conductivity_w_mk",0.0)), float(sub.get("heat_capacity_j_kgk",0.0)),
		float(sub.get("thermal_diffusivity_m2_s",0.0)), float(sub.get("hardness_mohs_approx",0.0))
	])
	lines.append("Weathering %.3f | oxidation %.3f | hydration %.3f | moisture %.3f | organics %.3f" % [
		float(sub.get("weathering_index",0.0)), float(sub.get("oxidation_index",0.0)),
		float(sub.get("hydration_index",0.0)), float(sub.get("moisture_fraction",0.0)),
		float(sub.get("organic_fraction",0.0))
	])

	lines.append("\n[b]SURFACE COVER[/b]")
	var covers: Dictionary = surf.get("covers", {})
	for k in covers.keys():
		if float(covers[k]) > 0.001:
			lines.append("%-12s %6.2f%%" % [String(k), float(covers[k])*100.0])
	if String(surf.get("liquid_species","")) != "":
		lines.append("Liquid species: %s   depth: %.3f m" % [surf.get("liquid_species",""), float(surf.get("liquid_depth_m",0.0))])
	if String(surf.get("frost_species","")) != "":
		lines.append("Frost/ice species: %s   equivalent depth: %.3f m" % [surf.get("frost_species",""), float(surf.get("frost_equivalent_depth_m",0.0))])
	var water_table := float(surf.get("water_table_depth_m", INF))
	if is_finite(water_table):
		lines.append("Nearest condensed-reservoir table: %.3f m below surface" % water_table)

	var hydro: Dictionary = r.get("hydrosphere", {})
	lines.append("\n[b]PLANETARY CONDENSED RESERVOIR[/b]")
	for s in hydro.get("mean_equivalent_depth_m", {}).keys():
		lines.append("%-5s mean equivalent depth %10.3f m   level %10.3f m" % [
			s, float(hydro.get("mean_equivalent_depth_m", {})[s]),
			float(hydro.get("sea_levels_m", {}).get(s, 0.0))
		])

	lines.append("\n[b]ATMOSPHERE[/b]")
	lines.append("Mean molar mass: %.5g kg/mol   Scale height: %.1f m   RH: %.1f%%   Wind: %.2f m/s" % [
		float(atm.get("mean_molar_mass_kg_mol",0.0)), float(atm.get("scale_height_m",0.0)),
		float(atm.get("relative_humidity",0.0))*100.0, float(atm.get("wind_m_s",0.0))
	])
	for s in atm.get("species", []):
		if float(s.get("mole_pct",0.0)) >= 0.001:
			lines.append("%-5s %9.4f%%   p=%s Pa   phase=%s" % [
				s.get("symbol","?"), float(s.get("mole_pct",0.0)),
				String.num_scientific(float(s.get("partial_pressure_pa",0.0))), s.get("phase_at_surface","")
			])

	lines.append("\n[b]ENERGY BALANCE — W/m²[/b]")
	var energy: Dictionary = r.get("energy", {})
	for k in ["solar","down_ir","geothermal","out_ir","sensible","latent","conductive","net"]:
		lines.append("%-12s %12.5g" % [k, float(energy.get(k,0.0))])

	lines.append("\n[b]MODEL STATUS[/b]")
	var coupling: Dictionary = model.get("coupling", {})
	lines.append("Thermal solver: %s | residual %.5g W/m² | converged: %s" % [
		model.get("thermal_convergence",""), float(model.get("thermal_residual_w_m2",0.0)),
		str(model.get("thermal_converged",false))
	])
	lines.append("Four-layer coupling: %s after %d iterations" % [
		"converged" if coupling.get("converged",false) else "approximate / not fully converged",
		int(coupling.get("iterations",0))
	])
	lines.append("Fidelity: thermal=%s; atmosphere=%s; minerals=%s" % [
		model.get("fidelity",{}).get("thermal",""), model.get("fidelity",{}).get("atmosphere",""),
		model.get("fidelity",{}).get("minerals","")
	])
	lines.append("[color=#c9a46a]Approximations: %s[/color]" % ", ".join(model.get("approximation_flags",[])))
	return "\n".join(lines)

func _sorted_keys_by_value(values: Dictionary) -> Array:
	var keys := values.keys()
	keys.sort_custom(func(a, b): return float(values[a]) > float(values[b]))
	return keys
