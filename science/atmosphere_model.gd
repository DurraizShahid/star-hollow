# atmosphere_model.gd
# -----------------------------------------------------------------------------
# Construction and behaviour of the planetary atmosphere.
#
# RESERVOIR MODEL (documented; fidelity = simplified + heuristic):
#   1. For each volatile species, the planet's reservoir mass is
#        m_s = volatile_inventory[s] * volatility_fraction * M_planet
#      A (degas_fraction) of the reservoir is available to the atmosphere.
#   2. The column mass per unit area is m_s / (4 pi R^2), giving a "would-be"
#      surface partial pressure  P_s = g * column_mass.
#   3. CONSATURATION / COLD-TRAP step: for condensable species, the vapour
#      is not entirely gaseous at planetary temperatures; atmospheric content
#      is capped near a fraction (cold_trap_ratio) of their saturation vapour
#      pressure evaluated at the planet's reference surface temperature. The
#      excess is partitioned to condensed surface ices/liquids (handled by the
#      per-cell phase solver).
#   4. Resulting partial pressures set the mole fractions; total pressure is
#      the sum. Ideal-gas density / scale height follow.
#
# GREENHOUSE (heuristic, documented, not full radiative transfer):
#   tau_IR = sum_s p_s/(1e5 Pa) * weight_s
#   T_surface ~ T_eq * (1 + 0.75 tau_IR)^(1/4)      (gray-greenhouse estimate)
# The gray model is an APPROXIMATION; never labeled as full radiative transfer.
# -----------------------------------------------------------------------------
class_name AtmosphereModel
extends RefCounted

## Heuristic IR cross-section weights relative to CO2 (renderer-independent).
const GHEIGHT_WEIGHTS := {
	"H2O": 2.0, "CO2": 1.0, "CH4": 1.6, "NH3": 1.2, "SO2": 0.9, "CO": 0.8,
	"N2": 0.03, "H2": 0.06, "O2": 0.02, "He": 0.0, "Ar": 0.015,
}

const NOMINAL_SPECIES := ["H2", "He", "N2", "O2", "CO2", "CO", "H2O", "CH4", "NH3", "SO2", "Ar"]

## Build the global atmosphere from planet parameters.
static func build(planet: PlanetParameters) -> AtmosphereState:
	var atm := AtmosphereState.new()
	atm.gravity = planet.surface_gravity

	var volumetric := _reservoir_column_pressure(planet)
	var reference_temp := _reference_temperature(planet)
	atm.temperature = reference_temp

	var cold_trap := _cold_trap_ratio(planet)
	var partial := {}
	# First pass: determine which species condense at the reference temperature.
	for s in volumetric.keys():
		var p_would: float = volumetric[s]
		var d := SpeciesDatabase.get_species(s)
		var p_cap := p_would
		if d["t_triple"] != null:
			# condensable assessment at reference temp
			var p_sat := _sat_at_reference(s, reference_temp)
			if p_sat > 0.0 and p_would > p_sat * cold_trap:
				p_cap = p_sat * cold_trap
				atm.notes.append("%s cold-trapped (p_would=%s Pa capped at %s Pa)" % [s, String.num_scientific(p_would), String.num_scientific(p_cap)])
			elif p_sat > 0.0 and p_would <= p_sat * cold_trap:
				atm.notes.append("%s kept gas (%s Pa < cap %s Pa)" % [s, String.num_scientific(p_would), String.num_scientific(p_sat * cold_trap)])
		# Non-condensables (H2, He, ...) get their full column; Ar has a triple but at
		# our temps it would condense on cold worlds only.
		partial[s] = maxf(p_cap, SciConstants.MIN_PRESSURE_PA)

	var p_total := 0.0
	for s in partial.keys():
		p_total += partial[s]
	atm.total_pressure = maxf(p_total, SciConstants.MIN_PRESSURE_PA)

	# Mole fractions.
	for s in partial.keys():
		atm.add_species(s, partial[s] / atm.total_pressure)

	# Ensure at least a dilute "residual" so ideal-gas math never divides by zero.
	if atm.species.is_empty():
		atm.add_species("N2", 1.0, "residual placeholder")
	atm.recompute()
	return atm

## Surface temperature estimate from gray greenhouse approximation.
static func surface_temperature_estimate(planet: PlanetParameters, atm: AtmosphereState) -> float:
	var tau := greenhouse_depth(atm)
	return planet.equilibrium_temperature * pow(1.0 + 0.75 * tau, 0.25)

static func greenhouse_depth(atm: AtmosphereState) -> float:
	var tau := 0.0
	for s in atm.species:
		var w: float = GHEIGHT_WEIGHTS.get(s, 0.0)
		tau += atm.partial_pressure(s) / 1.0e5 * w
	return clampf(tau, 0.0, 200.0)

static func _reservoir_column_pressure(planet: PlanetParameters) -> Dictionary:
	var surf_area := 4.0 * PI * planet.radius * planet.radius
	var out := {}
	for s in planet.volatile_inventory.keys():
		if not SpeciesDatabase.has(s):
			continue
		var frac: float = planet.volatile_inventory[s]
		if frac <= 0.0:
			continue
		var res_mass: float = frac * planet.volatility_fraction * planet.mass * planet.degas_fraction
		var column := res_mass / maxf(surf_area, 1e-9)
		var p_pa := planet.surface_gravity * column
		out[s] = p_pa
	return out

static func _reference_temperature(planet: PlanetParameters) -> float:
	# A crude "mean surface temperature" reference for reservoir capping using
	# the gray-greenhouse relation on equilibrium temperature.
	var tau_guess := 0.0
	for s in planet.volatile_inventory.keys():
		tau_guess += GHEIGHT_WEIGHTS.get(s, 0.0) * planet.volatile_inventory.get(s, 0.0)
	var t := planet.equilibrium_temperature * pow(1.0 + 0.75 * clampf(tau_guess, 0.0, 200.0), 0.25)
	return SciConstants.safe_clamp(t, SciConstants.MIN_TEMPERATURE_K, SciConstants.MAX_TEMPERATURE_K)

static func _cold_trap_ratio(planet: PlanetParameters) -> float:
	# Planets with strong volatile cold-traps (permanent polar ices, small) suppress
	# condensable atmosphere further. Heuristic table.
	match planet.preset:
		"marslike": return 0.02
		"plutolike": return 0.15
		"titanlike": return 0.20
		"airless_rocky": return 0.001
		_:
			return 0.05

static func _sat_at_reference(sym: String, reference_temp: float) -> float:
	var t := reference_temp
	var ref: float = SpeciesDatabase.triple_temperature(sym)
	if t < ref:
		return PhaseSolver.saturation_over_solid(sym, t)
	return PhaseSolver.saturation_liquid(sym, t)