# atmosphere_model.gd
# Global volatile reservoir + local hydrostatic atmospheric column.
# Greenhouse treatment remains a documented gray/heuristic approximation.
class_name AtmosphereModel
extends RefCounted

const GHEIGHT_WEIGHTS := {
	"H2O": 2.0, "CO2": 1.0, "CH4": 1.6, "NH3": 1.2, "SO2": 0.9, "CO": 0.8,
	"N2": 0.03, "H2": 0.06, "O2": 0.02, "He": 0.0, "Ar": 0.015,
}
const NOMINAL_SPECIES := ["H2", "He", "N2", "O2", "CO2", "CO", "H2O", "CH4", "NH3", "SO2", "Ar"]

static func build(planet: PlanetParameters) -> AtmosphereState:
	var atm := AtmosphereState.new()
	atm.gravity = planet.surface_gravity
	var volumetric := _reservoir_column_pressure(planet)
	var reference_temp := _reference_temperature(planet)
	atm.temperature = reference_temp
	var cold_trap := _cold_trap_ratio(planet)
	var partial := {}
	for s in volumetric.keys():
		var p_would: float = volumetric[s]
		var d := SpeciesDatabase.get_species(s)
		var p_cap := p_would
		if d["t_triple"] != null:
			var p_sat := _sat_at_reference(s, reference_temp)
			if p_sat > 0.0 and p_would > p_sat * cold_trap:
				p_cap = p_sat * cold_trap
				atm.notes.append("%s cold-trapped: %s -> %s Pa" % [
					s, String.num_scientific(p_would), String.num_scientific(p_cap)])
		partial[s] = maxf(p_cap, SciConstants.MIN_PRESSURE_PA)
	var p_total := 0.0
	for s in partial.keys():
		p_total += partial[s]
	atm.total_pressure = maxf(p_total, SciConstants.MIN_PRESSURE_PA)
	for s in partial.keys():
		atm.add_species(s, partial[s] / atm.total_pressure)
	if atm.species.is_empty():
		atm.add_species("N2", 1.0, "numerical residual atmosphere")
	atm.recompute()
	return atm

# Construct a local column without mutating the planet-wide reservoir.
# P(z) ~= P0 exp(-z/H); this is the isothermal hydrostatic approximation.
static func local_state(reference: AtmosphereState, elevation_m: float,
		air_temperature_k: float, wind_vector: Vector2 = Vector2.ZERO) -> AtmosphereState:
	var local := reference.copy_state()
	local.elevation_m = elevation_m
	local.temperature = SciConstants.safe_clamp(air_temperature_k,
		SciConstants.MIN_TEMPERATURE_K, SciConstants.MAX_TEMPERATURE_K)
	var exponent := clampf(-elevation_m / maxf(reference.scale_height, 1.0), -20.0, 20.0)
	local.total_pressure = reference.total_pressure * exp(exponent)
	local.wind_vector = wind_vector
	local.wind_speed_m_s = wind_vector.length()
	local.recompute()
	local.relative_humidity = _relative_humidity(local)
	return local

# Dry-adiabatic lapse estimate, blended with local radiative forcing.
# This is still a single-column approximation, not a circulation model.
static func initial_local_air_temperature(planet: PlanetParameters, reference: AtmosphereState,
		elevation_m: float, flux_factor: float) -> float:
	var cp_molar := _mixture_cp_molar(reference)
	var cp_mass := cp_molar / maxf(reference.mean_molar_mass, 1.0e-9)
	var dry_lapse := reference.gravity / maxf(cp_mass, 1.0) # K m^-1
	var base := surface_temperature_estimate(planet, reference)
	var radiative_factor := pow(maxf(flux_factor, 0.02), 0.08)
	var t := base * (0.92 + 0.08 * radiative_factor) - dry_lapse * elevation_m
	return SciConstants.safe_clamp(t, SciConstants.MIN_TEMPERATURE_K, SciConstants.MAX_TEMPERATURE_K)

# Near-surface air is relaxed toward the ground more strongly in dense/windy air.
# The coefficient is explicitly heuristic, but the direction of heat exchange is
# constrained by the solved surface/air temperature difference.
static func couple_air_temperature(current_air_k: float, surface_k: float,
		pressure_pa: float, wind_m_s: float) -> float:
	var pressure_factor := clampf(log(1.0 + pressure_pa) / log(1.0 + SciConstants.EARTH_PRESSURE), 0.0, 3.0)
	var coupling := clampf(0.025 + 0.10 * pressure_factor + 0.025 * wind_m_s, 0.02, 0.35)
	return lerpf(current_air_k, surface_k, coupling)

static func surface_temperature_estimate(planet: PlanetParameters, atm: AtmosphereState) -> float:
	var tau := greenhouse_depth(atm)
	return planet.equilibrium_temperature * pow(1.0 + 0.75 * tau, 0.25)

static func greenhouse_depth(atm: AtmosphereState) -> float:
	var tau := 0.0
	for s in atm.species:
		tau += atm.partial_pressure(s) / 1.0e5 * float(GHEIGHT_WEIGHTS.get(s, 0.0))
	return clampf(tau, 0.0, 200.0)

static func _mixture_cp_molar(atm: AtmosphereState) -> float:
	var cp := 0.0
	var total := 0.0
	for s in atm.species:
		var x: float = atm.mole_fraction(s)
		cp += x * Thermodynamics.gas_molar_cp(s)
		total += x
	return cp / maxf(total, 1.0e-12)

static func _relative_humidity(atm: AtmosphereState) -> float:
	var best := 0.0
	for s in atm.species:
		if not SpeciesDatabase.is_condensable(s):
			continue
		var p_sat := PhaseSolver.saturation_over_solid(s, atm.temperature) 			if atm.temperature < SpeciesDatabase.triple_temperature(s) 			else PhaseSolver.saturation_liquid(s, atm.temperature)
		if p_sat > 0.0:
			best = maxf(best, atm.partial_pressure(s) / p_sat)
	return clampf(best, 0.0, 1.0)

static func _reservoir_column_pressure(planet: PlanetParameters) -> Dictionary:
	var surf_area := 4.0 * PI * planet.radius * planet.radius
	var out := {}
	for s in planet.volatile_inventory.keys():
		if not SpeciesDatabase.has(s):
			continue
		var frac: float = planet.volatile_inventory[s]
		if frac <= 0.0:
			continue
		var res_mass := frac * planet.volatility_fraction * planet.mass * planet.degas_fraction
		var column := res_mass / maxf(surf_area, 1.0e-9)
		out[s] = planet.surface_gravity * column
	return out

static func _reference_temperature(planet: PlanetParameters) -> float:
	var tau_guess := 0.0
	for s in planet.volatile_inventory.keys():
		tau_guess += float(GHEIGHT_WEIGHTS.get(s, 0.0)) * float(planet.volatile_inventory.get(s, 0.0))
	var t := planet.equilibrium_temperature * pow(1.0 + 0.75 * clampf(tau_guess, 0.0, 200.0), 0.25)
	return SciConstants.safe_clamp(t, SciConstants.MIN_TEMPERATURE_K, SciConstants.MAX_TEMPERATURE_K)

static func _cold_trap_ratio(planet: PlanetParameters) -> float:
	match planet.preset:
		"marslike": return 0.02
		"plutolike": return 0.15
		"titanlike": return 0.20
		"airless_rocky": return 0.001
		_: return 0.05

static func _sat_at_reference(sym: String, reference_temp: float) -> float:
	var ref: float = SpeciesDatabase.triple_temperature(sym)
	return PhaseSolver.saturation_over_solid(sym, reference_temp) 		if reference_temp < ref else PhaseSolver.saturation_liquid(sym, reference_temp)
