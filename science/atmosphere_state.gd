# atmosphere_state.gd
# -----------------------------------------------------------------------------
# Snapshot of an atmosphere's composition and derived bulk properties.
#
# Units: pressure Pa, density kg m^-3, mean molar mass kg mol^-1, scale height m.
#
# Derived quantities use the ideal-gas law:
#   M_bar = sum_i x_i M_i
#   rho   = P M_bar / (R T)
#   H     = R T / (M_bar g_planet)
#   P_i   = x_i P_total
# -----------------------------------------------------------------------------
class_name AtmosphereState
extends RefCounted

var species: Array = []          # symbols (Array[String])
var mole_fractions := {}         # symbol -> mole fraction
var total_pressure := SciConstants.MIN_PRESSURE_PA
var temperature := 288.15        # reference temperature of this snapshot, K
var gravity := SciConstants.EARTH_GRAVITY

var mean_molar_mass := 0.0289644 # kg mol^-1 (filled by recompute())
var density := 1.225             # kg m^-3
var scale_height := 8500.0       # m
var greenhouse_tau := 0.0        # heuristic IR optical depth
var greenhouse_fidelity := SciConstants.FIDELITY_HEURISTIC:
	set(v):
		greenhouse_fidelity = v
var notes: Array = []            # approximation flags (Array[String])

func add_species(sym: String, xi: float, note: String = "") -> void:
	if not species.has(sym):
		species.append(sym)
	mole_fractions[sym] = xi
	if note != "" and not notes.has(note):
		notes.append(note)

func recompute() -> void:
	var mbar := 0.0
	var xsum := 0.0
	for s in species:
		var xi: float = mole_fractions[s]
		mbar += SpeciesDatabase.molar_mass(s) * xi
		xsum += xi
	if xsum <= 0.0:
		mean_molar_mass = 0.0289644
		return
	mean_molar_mass = mbar / xsum
	var t := SciConstants.safe_clamp(temperature, SciConstants.MIN_TEMPERATURE_K, SciConstants.MAX_TEMPERATURE_K)
	density = total_pressure * mean_molar_mass / (SciConstants.R_u * t)
	scale_height = SciConstants.R_u * t / (mean_molar_mass * maxf(gravity, 1e-9))
	greenhouse_tau = AtmosphereModel.greenhouse_depth(self)

func partial_pressure(sym: String) -> float:
	return mole_fractions.get(sym, 0.0) * total_pressure

func mole_fraction(sym: String) -> float:
	return mole_fractions.get(sym, 0.0)

func dominant_species() -> String:
	var best := ""
	var bx := -1.0
	for s in species:
		if mole_fractions[s] > bx:
			bx = mole_fractions[s]
			best = s
	return best

func describe() -> String:
	return "P=%s Pa, T=%.1f K, Mbar=%.4f g/mol, rho=%.4f kg/m3, H=%.0f m, tau_IR=%.3f" % [
		String.num_scientific(total_pressure), temperature, mean_molar_mass * 1e3, density, scale_height, greenhouse_tau]