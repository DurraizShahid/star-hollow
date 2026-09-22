# coupled_planet_solver.gd
# Scientific state is solved first; rendering is a pure consumer.
class_name CoupledPlanetSolver
extends RefCounted

const CELL_SIZE := 8.0
const CHUNK_CELLS := 16
const CHUNK_EDGE := CELL_SIZE * CHUNK_CELLS
const COVER_REF_DEPTH := 0.5
const MAX_COUPLED_ITER := 12
const COUPLED_TOL_K := 0.05

var planet: PlanetParameters
var geology: GeologyModel
var atmosphere: AtmosphereState       # planet reference column
var seed_value: int
var t_atm: float

func _init(p: PlanetParameters, seed_value_in: int = 0) -> void:
	planet = p
	seed_value = seed_value_in if seed_value_in != 0 else p.seed
	geology = GeologyModel.new(p, seed_value)
	atmosphere = AtmosphereModel.build(p)
	t_atm = AtmosphereModel.surface_temperature_estimate(p, atmosphere)

func rebalance_atmosphere() -> void:
	t_atm = AtmosphereModel.surface_temperature_estimate(planet, atmosphere)

static func chunk_origin(cx: int, cy: int) -> Vector2:
	return Vector2(cx * CHUNK_EDGE, cy * CHUNK_EDGE)

func generate_chunk(cx: int, cy: int) -> Dictionary:
	var origin := chunk_origin(cx, cy)
	var records: Array = []
	for iy in CHUNK_CELLS:
		for ix in CHUNK_CELLS:
			var x := origin.x + (ix + 0.5) * CELL_SIZE
			var y := origin.y + (iy + 0.5) * CELL_SIZE
			records.append(_solve_cell(x, y))
	return {"origin": origin, "cells": CHUNK_CELLS, "cell_size": CELL_SIZE, "records": records}

func _solve_cell(x: float, y: float) -> Dictionary:
	var boundary := geology.boundary_at(x, y)
	var wind := Vector2(boundary.wind_x, boundary.wind_y) * boundary.wind_speed
	var air_t := AtmosphereModel.initial_local_air_temperature(
		planet, atmosphere, boundary.elevation, boundary.flux_factor)
	var local_atm := AtmosphereModel.local_state(atmosphere, boundary.elevation, air_t, wind)

	# Chemistry begins from local bulk composition, not a visual/biome label.
	var budget := _rock_budget(boundary)
	var context := {
		"crust": boundary.crust_primary,
		"hydrated": local_atm.partial_pressure("H2O") > 100.0 and air_t > 240.0 and air_t < 350.0,
		"has_liquid_water": false,
		"carbonate_pressure": local_atm.partial_pressure("CO2"),
		"confidence": "norm",
	}
	var norm := EquilibriumSolver.norm(budget, context)
	var substrate := _make_substrate(budget, norm, boundary)
	var surface := _make_surface(substrate, boundary)
	var thermal := ThermalState.new()

	var previous_surface_t := INF
	var previous_air_t := local_atm.temperature
	var coupled_iterations := 0
	var coupled_converged := false

	# Fast climate/phase feedback loop.
	for i in range(MAX_COUPLED_ITER):
		thermal = ThermalModel.solve(planet, local_atm, {
			"flux_factor": boundary.flux_factor,
			"day_factor": boundary.day_factor,
			"t_atm": local_atm.temperature,
			"wind_speed": boundary.wind_speed,
			"surface": surface,
			"substrate": substrate,
		})
		_phase_covers(surface, thermal, local_atm)
		_apply_fast_surface_feedback(surface)

		var next_air_t := AtmosphereModel.couple_air_temperature(
			local_atm.temperature, thermal.temperature, local_atm.total_pressure, boundary.wind_speed)
		var dt_surface := absf(thermal.temperature - previous_surface_t) if is_finite(previous_surface_t) else INF
		var dt_air := absf(next_air_t - previous_air_t)
		coupled_iterations = i + 1
		previous_surface_t = thermal.temperature
		previous_air_t = local_atm.temperature
		local_atm = AtmosphereModel.local_state(atmosphere, boundary.elevation, next_air_t, wind)
		if dt_surface < COUPLED_TOL_K and dt_air < COUPLED_TOL_K and thermal.residual_w_m2 < 1.0:
			coupled_converged = true
			break

	# Slow surface layer: weathering, sediment and biology.
	var weathering := WeatheringModel.regolith(surface, substrate, thermal, boundary, local_atm)
	substrate.regolith_thickness = float(weathering.get("thick", 0.0))
	substrate.weathering_index = clampf(substrate.regolith_thickness / 30.0, 0.0, 1.0)
	substrate.hydration_index = 1.0 if surface.has_liquid_or_frost("H2O") else 0.0
	substrate.oxidation_index = _oxidation_index(substrate, local_atm, thermal)
	substrate.moisture_fraction = surface.liquid_cover if surface.liquid_species == "H2O" else 0.0

	var sediment := SedimentModel.cover(boundary, weathering, thermal.temperature > 300.0)
	surface.sediment_cover = float(sediment.get("cover", 0.0))
	surface.sediment_kind = String(sediment.get("kind", ""))
	_populate_surface_cover(surface, substrate, boundary, sediment, weathering)

	var bio := BiosphereModel.assess(thermal, surface, local_atm, boundary, planet)
	surface.organic_cover = maxf(surface.organic_cover, float(bio.get("organic_cover", 0.0)))
	var biomass := float(bio.get("biomass", 0.0))
	if biomass > 0.0 and not String(bio.get("label", "")).contains("tholin"):
		surface.vegetation_cover = clampf(biomass / 2.4, 0.0, 1.0)
		surface.vegetation_style = String(bio.get("label", ""))
	substrate.organic_fraction = surface.organic_cover

	# Slow covers alter radiation/insulation, so close the loop again.
	_apply_slow_surface_feedback(surface, sediment)
	for _j in range(3):
		thermal = ThermalModel.solve(planet, local_atm, {
			"flux_factor": boundary.flux_factor,
			"day_factor": boundary.day_factor,
			"t_atm": local_atm.temperature,
			"wind_speed": boundary.wind_speed,
			"surface": surface,
			"substrate": substrate,
		})
		_phase_covers(surface, thermal, local_atm)
		_apply_fast_surface_feedback(surface)
		var next_air := AtmosphereModel.couple_air_temperature(
			local_atm.temperature, thermal.temperature, local_atm.total_pressure, boundary.wind_speed)
		local_atm = AtmosphereModel.local_state(atmosphere, boundary.elevation, next_air, wind)

	surface.normalize_covers()
	var classification := MaterialClassifier.classify(surface, substrate, thermal, sediment)
	surface.dominant_label = classification.get("label", "unclassified")
	surface.dominant_kind = classification.get("kind", "unknown")
	surface.materials = classification.get("materials", [])

	return {
		"x": x, "y": y, "position": Vector2(x, y),
		"boundary": boundary,
		"substrate": substrate,
		"surface": surface,
		"thermal": thermal,
		"atmosphere": local_atm,
		"weathering": weathering,
		"sediment": sediment,
		"biosphere": bio,
		"classification": classification,
		"coupling": {
			"iterations": coupled_iterations,
			"converged": coupled_converged,
			"temperature_tolerance_k": COUPLED_TOL_K,
			"thermal_residual_w_m2": thermal.residual_w_m2,
		},
	}

func _rock_budget(boundary: GeologyModel.CellBoundary) -> Dictionary:
	var e_primary := GeologyProvinces.crust_enrichment(boundary.crust_primary)
	var e_secondary := GeologyProvinces.crust_enrichment(boundary.crust_secondary)
	var blend2 := clampf(boundary.province_blend * 2.0, 0.0, 1.0)
	var budget := {}
	var total := 0.0
	for e in planet.rock_elements.keys():
		var base_f: float = planet.rock_elements[e]
		if base_f <= 0.0:
			continue
		var ce: float = float(e_primary.get(e, 1.0)) * (1.0 - blend2) + float(e_secondary.get(e, 1.0)) * blend2
		var v := base_f * ce * float(boundary.enrichment.get(e, 1.0))
		if v > 1.0e-12:
			budget[e] = v
			total += v
	for e in budget.keys():
		budget[e] = budget[e] / maxf(total, 1.0e-12)
	return budget

func _make_substrate(budget: Dictionary, norm: Dictionary, boundary: GeologyModel.CellBoundary) -> SubstrateState:
	var sub := SubstrateState.new()
	sub.bedrock_minerals = norm.get("minerals", [])
	sub.elemental_mass_fraction = budget
	sub.normative_notes = norm.get("notes", [])
	sub.residue = norm.get("residue", {})
	sub.crust_style = boundary.crust_primary
	sub.age_years = planet.age
	sub.fidelity = SciConstants.FIDELITY_SIMPLIFIED_PHYSICAL

	var k := 2.1
	var den := 2700.0
	var cp := 900.0
	var hardness := 5.5
	var top := sub.dominant_mineral()
	if top.contains("Quartz"):
		k = 3.2; den = 2650.0; hardness = 7.0
	elif top.contains("Olivine") or top.contains("Pyroxene") or top.contains("Enstatite") or top.contains("Diopside"):
		k = 2.7; den = 3200.0; hardness = 6.5
	elif top.contains("Hematite") or top.contains("Magnetite") or top.contains("Cementite"):
		k = 4.5; den = 5100.0; hardness = 6.0
	elif top.contains("Halite"):
		k = 6.0; den = 2170.0; hardness = 2.5
	elif top.contains("Gypsum"):
		k = 2.0; den = 2320.0; hardness = 2.0
	elif top.contains("Graphite"):
		k = 5.0; den = 2250.0; hardness = 1.5
	sub.thermal_conductivity = k
	sub.density = den
	sub.heat_capacity = cp
	sub.hardness_mohs_approx = hardness
	sub.porosity = clampf(0.48 - boundary.slope * 0.28 + boundary.fracture_density * 0.12, 0.04, 0.65)
	sub.grain_size_mean_m = pow(10.0, lerpf(-4.5, -1.2, clampf(boundary.slope + 0.3 * boundary.fracture_density, 0.0, 1.0)))
	sub.grain_size_sigma = 1.4 + 2.0 * boundary.fracture_density
	sub.roughness_rms_m = 0.002 + 0.25 * boundary.slope
	sub.recompute_thermophysical()
	return sub

func _make_surface(substrate: SubstrateState, boundary: GeologyModel.CellBoundary) -> SurfaceState:
	var s := SurfaceState.new()
	s.roughness = clampf(boundary.slope * 0.6 + boundary.fracture_density * 0.25, 0.05, 0.9)
	s.relief = clampf(boundary.slope * 900.0, 0.0, 300.0)
	s.albedo = _mineral_reflectance(substrate)
	s.emissivity = clampf(0.98 - s.roughness * 0.06, 0.80, 0.98)
	substrate.albedo = s.albedo
	substrate.emissivity = s.emissivity
	return s

func _mineral_reflectance(substrate: SubstrateState) -> float:
	var weighted := 0.0
	var wsum := 0.0
	for m in substrate.bedrock_minerals:
		var f: float = float(m.get("fraction", 0.0))
		var name := String(m.get("name", ""))
		var a := 0.20
		if name.contains("Quartz") or name.contains("Feldspar"): a = 0.32
		elif name.contains("Hematite"): a = 0.12
		elif name.contains("Magnetite") or name.contains("Graphite"): a = 0.07
		elif name.contains("Halite") or name.contains("Gypsum") or name.contains("Calcite"): a = 0.50
		elif name.contains("Olivine") or name.contains("Pyroxene") or name.contains("Enstatite"): a = 0.16
		weighted += a * f
		wsum += f
	return clampf(weighted / maxf(wsum, 1.0e-9), 0.03, 0.70) if wsum > 0.0 else 0.20

func _phase_covers(surface: SurfaceState, thermal: ThermalState, atm: AtmosphereState) -> void:
	surface.liquid_cover = 0.0
	surface.liquid_species = ""
	surface.frost_cover = 0.0
	surface.frost_species = ""
	surface.volatile_reservoir.clear()
	surface.phase_notes.clear()
	var best_species := ""
	var best_mass := 0.0
	for s in atm.species:
		if not SpeciesDatabase.is_condensable(s):
			continue
		var p_partial := atm.partial_pressure(s)
		if p_partial <= SciConstants.MIN_PRESSURE_PA:
			continue
		var supersat := PhaseSolver.supersaturation_ratio(s, thermal.temperature, p_partial)
		if supersat <= 1.0:
			continue
		var column_mass := p_partial / maxf(atm.gravity, 1.0e-9)
		var excess := column_mass * clampf((supersat - 1.0) / supersat, 0.0, 0.98)
		surface.volatile_reservoir[s] = excess
		if excess > best_mass:
			best_mass = excess
			best_species = s
	if best_species == "":
		return

	var density := SpeciesDatabase.liquid_density(best_species)
	if density == null or density <= 0.0:
		density = SpeciesDatabase.solid_density(best_species)
	if density == null or density <= 0.0:
		density = 1000.0
	var cover := clampf((best_mass / density) / COVER_REF_DEPTH, 0.0, 1.0)
	var phase := PhaseSolver.phase_of(best_species, thermal.temperature, atm.partial_pressure(best_species))
	match phase.get("phase", PhaseSolver.PHASE_VAPOR):
		PhaseSolver.PHASE_LIQUID:
			surface.liquid_cover = cover
			surface.liquid_species = best_species
		PhaseSolver.PHASE_SOLID:
			surface.frost_cover = cover
			surface.frost_species = best_species
		_:
			return
	surface.phase_notes.append("%s %s stable; condensed column %.3g kg/m2" % [
		best_species, phase.get("phase", "?"), best_mass])
	surface.humidity = atm.relative_humidity

func _apply_fast_surface_feedback(surface: SurfaceState) -> void:
	if surface.frost_cover > 0.0:
		surface.albedo = lerpf(surface.albedo, 0.76, surface.frost_cover)
		surface.emissivity = lerpf(surface.emissivity, 0.97, surface.frost_cover)
	if surface.liquid_cover > 0.0:
		surface.albedo = lerpf(surface.albedo, 0.07, surface.liquid_cover)
		surface.roughness *= 1.0 - 0.75 * surface.liquid_cover

func _apply_slow_surface_feedback(surface: SurfaceState, sediment: Dictionary) -> void:
	if surface.sediment_cover > 0.0:
		var sediment_a := 0.28 if String(sediment.get("kind", "")) in ["sand", "silt"] else 0.20
		surface.albedo = lerpf(surface.albedo, sediment_a, surface.sediment_cover * 0.55)
	if surface.organic_cover > 0.0:
		surface.albedo = lerpf(surface.albedo, 0.12, surface.organic_cover * 0.45)
	if surface.vegetation_cover > 0.0:
		surface.albedo = lerpf(surface.albedo, 0.16, surface.vegetation_cover * 0.35)

func _populate_surface_cover(surface: SurfaceState, substrate: SubstrateState,
		boundary: GeologyModel.CellBoundary, sediment: Dictionary, weathering: Dictionary) -> void:
	var slope := boundary.slope
	var fracture := boundary.fracture_density
	surface.rock_cover = clampf((1.0 - surface.sediment_cover) * (0.35 + fracture * 0.55), 0.0, 1.0)
	surface.boulder_cover = clampf(slope * fracture * 0.55, 0.0, 0.65)
	surface.pebble_cover = clampf(substrate.weathering_index * (1.0 - slope) * 0.6, 0.0, 0.75)
	surface.dust_cover = clampf(surface.sediment_cover * (0.7 if surface.sediment_kind in ["silt", "clay"] else 0.2), 0.0, 1.0)
	var secondary: Array = weathering.get("secondary", [])
	surface.salt_cover = 0.25 if secondary.any(func(v): return String(v).contains("Calcite") or String(v).contains("Gypsum")) else 0.0

func _oxidation_index(substrate: SubstrateState, atm: AtmosphereState, thermal: ThermalState) -> float:
	var oxidants := atm.partial_pressure("O2") + 0.2 * atm.partial_pressure("H2O") + 0.02 * atm.partial_pressure("CO2")
	var fe := float(substrate.elemental_mass_fraction.get("Fe", 0.0))
	var kinetic := clampf((thermal.temperature - 180.0) / 250.0, 0.0, 1.0)
	return clampf(log(1.0 + oxidants) / 14.0 * fe * 8.0 * kinetic, 0.0, 1.0)

static func describe_cell(record: Dictionary) -> String:
	var s: SurfaceState = record["surface"]
	var t: ThermalState = record["thermal"]
	var a: AtmosphereState = record["atmosphere"]
	return "(%.0f,%.0f m) %s T=%.1fK P=%.3gPa liq=%.2f frost=%.2f" % [
		record["x"], record["y"], record["classification"].get("label", "?"),
		t.temperature, a.total_pressure, s.liquid_cover, s.frost_cover]
