# atmosphere_state.gd
class_name AtmosphereState
extends RefCounted

var species: Array = []
var mole_fractions := {}
var total_pressure := SciConstants.MIN_PRESSURE_PA
var temperature := 288.15
var gravity := SciConstants.EARTH_GRAVITY
var elevation_m := 0.0
var wind_speed_m_s := 0.0
var wind_vector := Vector2.ZERO
var relative_humidity := 0.0

var mean_molar_mass := 0.0289644
var density := 1.225
var scale_height := 8500.0
var greenhouse_tau := 0.0
var greenhouse_fidelity := SciConstants.FIDELITY_HEURISTIC
var notes: Array = []

func add_species(sym: String, xi: float, note: String = "") -> void:
	if not species.has(sym):
		species.append(sym)
	mole_fractions[sym] = maxf(0.0, xi)
	if note != "" and not notes.has(note):
		notes.append(note)

func recompute() -> void:
	var mbar := 0.0
	var xsum := 0.0
	for s in species:
		var xi: float = maxf(0.0, mole_fractions.get(s, 0.0))
		mbar += SpeciesDatabase.molar_mass(s) * xi
		xsum += xi
	if xsum <= 0.0:
		mean_molar_mass = 0.0289644
	else:
		mean_molar_mass = mbar / xsum
	var t := SciConstants.safe_clamp(temperature, SciConstants.MIN_TEMPERATURE_K, SciConstants.MAX_TEMPERATURE_K)
	total_pressure = SciConstants.safe_clamp(total_pressure, SciConstants.MIN_PRESSURE_PA, SciConstants.MAX_PRESSURE_PA)
	density = minf(SciConstants.MAX_DENSITY, total_pressure * mean_molar_mass / (SciConstants.R_u * t))
	scale_height = SciConstants.R_u * t / maxf(mean_molar_mass * gravity, 1.0e-12)
	greenhouse_tau = AtmosphereModel.greenhouse_depth(self)

func partial_pressure(sym: String) -> float:
	return mole_fractions.get(sym, 0.0) * total_pressure

func mole_fraction(sym: String) -> float:
	return mole_fractions.get(sym, 0.0)

func dominant_species() -> String:
	var best := ""
	var bx := -1.0
	for s in species:
		var x: float = mole_fractions.get(s, 0.0)
		if x > bx:
			bx = x
			best = s
	return best

func copy_state() -> AtmosphereState:
	var a := AtmosphereState.new()
	a.species = species.duplicate()
	a.mole_fractions = mole_fractions.duplicate()
	a.total_pressure = total_pressure
	a.temperature = temperature
	a.gravity = gravity
	a.elevation_m = elevation_m
	a.wind_speed_m_s = wind_speed_m_s
	a.wind_vector = wind_vector
	a.relative_humidity = relative_humidity
	a.greenhouse_fidelity = greenhouse_fidelity
	a.notes = notes.duplicate()
	a.recompute()
	return a

func describe() -> String:
	return "P=%s Pa, T=%.1f K, Mbar=%.4f g/mol, rho=%.4f kg/m3, H=%.0f m, z=%.0f m" % [
		String.num_scientific(total_pressure), temperature, mean_molar_mass * 1e3,
		density, scale_height, elevation_m]
