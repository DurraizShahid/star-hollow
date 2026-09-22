# phase_solver.gd
# -----------------------------------------------------------------------------
# Single-component phase identification from real phase-boundary data.
#
# Determines the stable phase (solid / liquid / vapor / supercritical) of a
# pure substance at (T, P) using the boundary curves from thermodynamics.gd,
# which are anchored on real triple / critical point data (see SpeciesDatabase).
#
# This respects real behaviour: CO2 is NOT treated like water. Below the
# CO2 triple pressure (5.18 bar) there is no liquid ever, only solid/vapor —
# so the code cannot "produce a CO2 ocean" on a low-pressure world.
# -----------------------------------------------------------------------------
class_name PhaseSolver
extends RefCounted

const PHASE_SOLID := "solid"
const PHASE_LIQUID := "liquid"
const PHASE_VAPOR := "vapor"
const PHASE_SUPERCRITICAL := "supercritical"

## Returns { "phase": ..., "saturation_pressure": Pa, "reason": String }.
static func phase_of(sym: String, temperature_k: float, pressure_pa: float) -> Dictionary:
	var t := SciConstants.safe_clamp(temperature_k, SciConstants.MIN_TEMPERATURE_K, SciConstants.MAX_TEMPERATURE_K)
	var p := SciConstants.safe_clamp(pressure_pa, SciConstants.MIN_PRESSURE_PA, SciConstants.MAX_PRESSURE_PA)
	if not SpeciesDatabase.has(sym):
		return { "phase": PHASE_VAPOR, "saturation_pressure": 0.0, "reason": "unknown species" }

	var d := SpeciesDatabase.get_species(sym)
	var tc = d["t_crit"]
	var pc = d["p_crit"]
	var tt = d["t_triple"]
	var pt = d["p_triple"]

	# Supercritical / gas above critical.
	if tc != null and t >= tc:
		var phase := PHASE_SUPERCRITICAL if (pc != null and p >= pc) else PHASE_VAPOR
		return { "phase": phase, "saturation_pressure": 0.0, "reason": "above critical" }

	# Helium-like: no triple point, gas in our range.
	if tt == null:
		return { "phase": PHASE_VAPOR, "saturation_pressure": 0.0, "reason": "no triple point" }

	if p >= pt:
		if t < tt:
			return { "phase": PHASE_SOLID, "saturation_pressure": saturation_over_solid(sym, t), "reason": "below triple temperature" }
		var t_melt := Thermodynamics.melting_temperature(sym, p)
		if t < t_melt:
			return { "phase": PHASE_SOLID, "saturation_pressure": saturation_over_solid(sym, t), "reason": "below melting curve" }
		var p_sat := saturation_liquid(sym, t)
		if p > p_sat:
			return { "phase": PHASE_LIQUID, "saturation_pressure": p_sat, "reason": "liquid stable" }
		return { "phase": PHASE_VAPOR, "saturation_pressure": p_sat, "reason": "above boiling curve" }
	else:
		# Below triple pressure: only solid <-> vapor (sublimation curve).
		var t_sub := Thermodynamics.sublimation_temperature(sym, p)
		if t < t_sub:
			var sp := saturation_over_solid(sym, t)
			return { "phase": PHASE_SOLID, "saturation_pressure": sp, "reason": "below sublimation curve" }
		return { "phase": PHASE_VAPOR, "saturation_pressure": saturation_over_solid(sym, t), "reason": "above sublimation curve" }

static func saturation_over_solid(sym: String, t: float) -> float:
	return Thermodynamics.saturation_vapor_pressure_solid(sym, t)

static func saturation_liquid(sym: String, t: float) -> float:
	return Thermodynamics.saturation_vapor_pressure_liquid(sym, t)

## If a vapour with partial pressure p_partial at temperature T is at or
## below its stable phase boundary, is it saturated? Returns supersaturation
## ratio S >= 1 when saturated (or below freezing for liquids).
static func supersaturation_ratio(sym: String, temperature_k: float, partial_pressure: float) -> float:
	var t := SciConstants.safe_clamp(temperature_k, SciConstants.MIN_TEMPERATURE_K, SciConstants.MAX_TEMPERATURE_K)
	var p := SciConstants.safe_clamp(partial_pressure, SciConstants.MIN_PRESSURE_PA, SciConstants.MAX_PRESSURE_PA)
	if not SpeciesDatabase.has(sym):
		return 0.0
	var d := SpeciesDatabase.get_species(sym)
	if d["t_triple"] == null:
		return 0.0
	var p_sat := 0.0
	if t < d["t_triple"]:
		p_sat = saturation_over_solid(sym, t)
	else:
		p_sat = saturation_liquid(sym, t)
	if p_sat <= 0.0:
		return 0.0
	return p / p_sat

## Condensation temperature at a given partial pressure.
static func condensation_temperature(sym: String, partial_pressure: float) -> float:
	return Thermodynamics.sublimation_temperature(sym, partial_pressure) \
		if partial_pressure < SpeciesDatabase.triple_pressure(sym) else \
		Thermodynamics.vaporization_temperature(sym, partial_pressure)