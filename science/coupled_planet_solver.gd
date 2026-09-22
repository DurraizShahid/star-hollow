# coupled_planet_solver.gd
# -----------------------------------------------------------------------------
# Orchestrates the per-chunk, per-cell solution chain from boundary conditions
# to a complete scientific material/state record:
#
#   boundary (geology)                                  [deterministic, pure]
#     -> rock budget   = planet rock_elements
#                       x crust enrichment (primary/secondary blend)
#                       x local per-element enrichment   [bounded noise]
#     -> normative mineral allocation (moles conserved)  EquilibriumSolver
#     -> substrate thermophysics
#     -> surface radiative properties from mineralogy
#     -> energy-balance T solve                          ThermalModel
#     -> phase cover (frost / liquid) + latent re-solve  PhaseSolver
#     -> weathering / sediment / biosphere / classifier
#
# The result is a per-cell record carrying *states* (not colors); the game
# layer turns these into renderable output. Everything is a pure function of
# (x, y) + seed + global atmosphere, so chunk borders join continuously.
#
# Fidelity notes: the atmosphere is a single global reservoir (no per-cell
# pressure advection); the thermal model is a single-layer gray approach with
# static illumination; cover condensation is a heuristic column-mass split.
# Each of these is documented in docs/science/*.md.
# -----------------------------------------------------------------------------
class_name CoupledPlanetSolver
extends RefCounted

const CELL_SIZE := 8.0               # metres per simulation cell
const CHUNK_CELLS := 16              # cells per chunk edge
const CHUNK_EDGE := CELL_SIZE * CHUNK_CELLS   # 128 m
const COVER_REF_DEPTH := 0.5         # m of liquid-equivalent at which a volatile covers a cell
const COCONDENSATION_EPS := 0.25

var planet: PlanetParameters
var geology: GeologyModel
var atmosphere: AtmosphereState
var seed_value: int

## Global atmospheric surface temperature used by energy balances (single column).
var t_atm: float

func _init(p: PlanetParameters, seed_value_in: int = 0) -> void:
	planet = p
	seed_value = seed_value_in if seed_value_in != 0 else p.seed
	geology = GeologyModel.new(p, seed_value)
	atmosphere = AtmosphereModel.build(p)
	t_atm = AtmosphereModel.surface_temperature_estimate(p, atmosphere)

## Re-derive the global atmospheric temperature (e.g. after coupling iterations).
func rebalance_atmosphere() -> void:
	t_atm = AtmosphereModel.surface_temperature_estimate(planet, atmosphere)

## World-space origin (metres, cell-centre coords) of a chunk.
static func chunk_origin(cx: int, cy: int) -> Vector2:
	return Vector2(cx * CHUNK_EDGE, cy * CHUNK_EDGE)

## Generate a chunk's cells. Returns { origin: Vector2, cells: int, records: Array }
func generate_chunk(cx: int, cy: int) -> Dictionary:
	var origin := chunk_origin(cx, cy)
	var records: Array = []
	for iy in CHUNK_CELLS:
		for ix in CHUNK_CELLS:
			var x := origin.x + (ix + 0.5) * CELL_SIZE
			var y := origin.y + (iy + 0.5) * CELL_SIZE
			records.append(_solve_cell(x, y))
	return { "origin": origin, "cells": CHUNK_CELLS, "cell_size": CELL_SIZE, "records": records }

# ---- per-cell pipeline ------------------------------------------------------

func _solve_cell(x: float, y: float) -> Dictionary:
	var boundary := geology.boundary_at(x, y)

	# 1. Provisional temperature (drives hydration guesses used by the norm).
	var prov_surface := SurfaceState.new()
	prov_surface.albedo = _albedo_guess(boundary)
	var prov_ctx := {
		"flux_factor": boundary.flux_factor, "day_factor": boundary.day_factor,
		"t_atm": t_atm, "wind_speed": boundary.wind_speed, "surface": prov_surface,
	}
	var t_prov := ThermalModel.solve(planet, atmosphere, prov_ctx).temperature

	# 2. Rock budget + mineralogy (norm).
	var budget := _rock_budget(boundary)
	var context := {
		"crust": boundary.crust_primary,
		"hydrated": _hydration_guess(t_prov, boundary),
		"has_liquid_water": false,
		"carbonate_pressure": atmosphere.partial_pressure("CO2"),
		"confidence": "norm",
	}
	var norm := EquilibriumSolver.norm(budget, context)
	var substrate := _make_substrate(budget, norm, boundary)

	# 3. Surface radiative properties from resolved mineralogy.
	var surface := _make_surface(substrate, boundary)

	# 4. Final energy-balance solve.
	var ctx := {
		"flux_factor": boundary.flux_factor, "day_factor": boundary.day_factor,
		"t_atm": t_atm, "wind_speed": boundary.wind_speed, "surface": surface,
	}
	var thermal := ThermalModel.solve(planet, atmosphere, ctx)

	# 5. Phase cover determination; if a volatile condenses, re-solve once so the
	#    energy balance reflects the wet/icy surface (latent + albedo feedback).
	_phase_covers(surface, thermal, atmosphere)
	if surface.liquid_cover >= 0.02 or surface.frost_cover >= 0.02:
		var ctx2 := {
			"flux_factor": boundary.flux_factor, "day_factor": boundary.day_factor,
			"t_atm": t_atm, "wind_speed": boundary.wind_speed, "surface": surface,
		}
		thermal = ThermalModel.solve(planet, atmosphere, ctx2)

	# 6. Weathering / regolith production.
	var weathering := WeatheringModel.regolith(surface, substrate, thermal, boundary, atmosphere)
	substrate.regolith_thickness = weathering["thick"]

	# 7. Sediment cover.
	var sediment := SedimentModel.cover(boundary, weathering, thermal.temperature > 300.0)
	surface.sediment_cover = sediment["cover"]

	# 8. Biosphere assessment.
	var bio := BiosphereModel.assess(thermal, surface, atmosphere, boundary, planet)
	surface.organic_cover = bio["organic_cover"]

	# 9. Scientific classification (quantitative thresholds only).
	var classification := MaterialClassifier.classify(surface, substrate, thermal, sediment)
	surface.dominant_label = classification["label"]
	surface.dominant_kind = classification["kind"]

	return {
		"x": x, "y": y, "position": Vector2(x, y),
		"boundary": boundary,
		"substrate": substrate,
		"surface": surface,
		"thermal": thermal,
		"atmosphere": atmosphere,
		"weathering": weathering,
		"sediment": sediment,
		"biosphere": bio,
		"classification": classification,
	}

# ---- state factories --------------------------------------------------------

## Base rock budget: planet average x crust enrichment (primary/secondary blend)
## x local per-element enrichment, normalized so mass fractions sum to 1.
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
		var ce: float = e_primary.get(e, 1.0) * (1.0 - blend2) + e_secondary.get(e, 1.0) * blend2
		var local: float = boundary.enrichment.get(e, 1.0)
		var v := base_f * ce * local
		if v > 1e-12:
			budget[e] = v
			total += v
	if total <= 0.0:
		return planet.rock_elements.duplicate()
	for e in budget.keys():
		budget[e] = budget[e] / total
	return budget

func _make_substrate(budget: Dictionary, norm: Dictionary, boundary: GeologyModel.CellBoundary) -> SubstrateState:
	var sub := SubstrateState.new()
	sub.bedrock_minerals = norm["minerals"]
	sub.elemental_mass_fraction = budget
	sub.normative_notes = norm.get("notes", [])
	sub.residue = norm.get("residue", {})
	sub.crust_style = boundary.crust_primary
	sub.fidelity = SciConstants.FIDELITY_SIMPLIFIED_PHYSICAL

	# Thermophysical properties from the dominant mineralogy (empirical anchors).
	var k := 2.1
	var den := 2700.0
	var cp := 1050.0
	var top := sub.dominant_mineral()
	if top.contains("Quartz"):
		k = 3.2; den = 2650.0
	elif top.contains("Olivine") or top.contains("Pyroxene") or top.contains("Enstatite") or top.contains("Diopside"):
		k = 2.4; den = 3000.0
	elif top.contains("Hematite") or top.contains("Magnetite") or top.contains("Cementite"):
		k = 1.9; den = 5100.0
	elif top.contains("Halite") or top.contains("Anhydrite") or top.contains("Gypsum") or top.contains("Calcite"):
		k = 1.1; den = 2600.0
	elif top.contains("Graphite"):
		k = 5.0; den = 2200.0
	elif top.contains("Feldspar") or top.contains("Albite") or top.contains("Anorthite"):
		k = 2.3; den = 2620.0
	sub.thermal_conductivity = k
	sub.density = den
	sub.heat_capacity = cp
	sub.porosity = clampf(0.5 - boundary.slope * 0.25, 0.05, 0.6)
	sub.recompute_thermophysical()
	return sub

## Mineralogy -> solar reflectance (empirical anchors; albedo never a random field).
func _make_surface(substrate: SubstrateState, boundary: GeologyModel.CellBoundary) -> SurfaceState:
	var s := SurfaceState.new()
	var reflectance := _mineral_reflectance(substrate)
	var rough := clampf(boundary.slope * 0.6 + boundary.fracture_density * 0.25, 0.05, 0.9)
	s.roughness = rough
	s.relief = clampf(boundary.slope * 900.0, 0.0, 300.0)
	s.albedo = reflectance
	s.emissivity = clampf(0.98 - rough * 0.06, 0.80, 0.98)
	return s

const _REFLECTANCE := {
	"Quartz SiO2": 0.34,
	"K-Feldspar KAlSi3O8": 0.30,
	"Albite NaAlSi3O8": 0.32,
	"Anorthite CaAl2Si2O8": 0.28,
	"Diopside CaMgSi2O6": 0.14,
	"Enstatite MgSiO3": 0.16,
	"Forsterite Mg2SiO4": 0.18,
	"Fayalite Fe2SiO4": 0.11,
	"Corundum Al2O3": 0.25,
	"Hematite Fe2O3": 0.09,
	"Magnetite Fe3O4": 0.07,
	"Ilmenite FeTiO3": 0.09,
	"Cementite Fe3C": 0.08,
	"Pyrite FeS2": 0.09,
	"Graphite C": 0.06,
	"Halite NaCl": 0.50,
	"Anhydrite CaSO4": 0.45,
	"Gypsum CaSO4.2H2O": 0.47,
	"Calcite CaCO3": 0.40,
	"Apatite Ca5(PO4)3(OH)": 0.32,
}

func _mineral_reflectance(substrate: SubstrateState) -> float:
	var a := 0.20
	var wsum := 0.0
	for m in substrate.bedrock_minerals:
		var f: float = m.get("fraction", 0.0)
		if _REFLECTANCE.has(m["name"]):
			a += _REFLECTANCE[m["name"]] * f
			wsum += f
	if wsum > 0.0:
		a /= maxf(wsum, 1e-9)
	return clampf(a, 0.03, 0.62)

func _albedo_guess(boundary: GeologyModel.CellBoundary) -> float:
	var ce := GeologyProvinces.crust_enrichment(boundary.crust_primary)
	# Crude mineral-free proxy: darker volcanics, brighter sediment/evaporite crust.
	var base := 0.16
	if ce.get("Fe", 1.0) < 0.8:
		base = 0.09
	elif ce.get("Cl", 1.0) > 1.5 or ce.get("Ca", 1.0) > 1.2:
		base = 0.40
	return clampf(base, 0.06, 0.5)

# ---- phase cover ------------------------------------------------------------

## Determine stable condensed volatiles on the surface from (T, P).
## Uses the supersaturation ratio: when partial pressure exceeds local
## saturation the excess column mass condenses; one dominant species occupies
## the canopy (largest condensed column), subdominants recorded as notes.
func _phase_covers(surface: SurfaceState, thermal: ThermalState, atm: AtmosphereState) -> void:
	var condensed := {}
	for s in atm.species:
		if not SpeciesDatabase.is_condensable(s):
			continue
		var p_s := atm.partial_pressure(s)
		if p_s <= 0.0:
			continue
		var S := PhaseSolver.supersaturation_ratio(s, thermal.temperature, p_s)
		if S < 1.0:
			continue
		var col := p_s / maxf(atm.gravity, 1e-9)          # kg m^-2 vapour overhead
		var excess := col * clampf((S - 1.0) / (S + 1.0), 0.0, 0.95)
		condensed[s] = { "excess": excess, "S": S }

	if condensed.is_empty():
		surface.liquid_cover = 0.0
		surface.liquid_species = ""
		surface.frost_cover = 0.0
		surface.frost_species = ""
		return

	var winner := ""
	var winner_excess := -1.0
	for s in condensed.keys():
		if condensed[s]["excess"] > winner_excess:
			winner_excess = condensed[s]["excess"]
			winner = s

	var rho_liq := SpeciesDatabase.liquid_density(winner) if winner in condensed or SpeciesDatabase.has(winner) else 1000.0
	if rho_liq == null or rho_liq <= 0.0:
		rho_liq = 1000.0
	var depth := winner_excess / rho_liq                         # metres liquid-equivalent
	var cover := clampf(depth / COVER_REF_DEPTH, 0.0, 1.0)

	var t := thermal.temperature
	var triple: float = SpeciesDatabase.triple_temperature(winner)
	var is_liquid := t >= triple
	if is_liquid:
		surface.liquid_cover = cover
		surface.liquid_species = winner
	else:
		surface.frost_cover = cover
		surface.frost_species = winner

	surface.volatile_reservoir[winner] = winner_excess
	surface.phase_notes.append("%s condenses (S=%.2f, p=%s Pa, T=%.0f K)" % [
		winner, condensed[winner]["S"], String.num_scientific(atm.partial_pressure(winner)), t])
	for s in condensed.keys():
		if s == winner:
			continue
		var minor: float = condensed[s]["excess"]
		if minor >= COCONDENSATION_EPS * winner_excess:
			surface.phase_notes.append("co-condensing %s (S=%.2f)" % [s, condensed[s]["S"]])

	# Relative humidity of the dominant volatile.
	var rho_air := maxf(atm.density, 1e-9)
	var delta := clampf(winner_excess / maxf(rho_air * 10.0, 1e-9), 0.0, 1.0)
	surface.humidity = clampf(delta, 0.0, 1.0)

# ---- small helpers ----------------------------------------------------------

func _hydration_guess(t_prov: float, boundary: GeologyModel.CellBoundary) -> bool:
	if t_prov < 240.0 or t_prov > 330.0:
		return false
	var p_h2o := atmosphere.partial_pressure("H2O")
	if p_h2o > 100.0:
		return true
	return atmosphere.partial_pressure("CO2") > 300.0 and t_prov > 260.0

## Greyscale debug facilitation: expose a human summary of a cell record.
static func describe_cell(record: Dictionary) -> String:
	var s: SurfaceState = record["surface"]
	var t: ThermalState = record["thermal"]
	var c: Dictionary = record["classification"]
	return "(%5.0f,%5.0f m) %-45s T=%5.1f K  A=%0.2f  liq=%0.2f %s  frost=%0.2f %s" % [
		record["x"], record["y"], c.get("label", "?"), t.temperature,
		s.albedo, s.liquid_cover, s.liquid_species, s.frost_cover, s.frost_species]