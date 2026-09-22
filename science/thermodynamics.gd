# thermodynamics.gd
# -----------------------------------------------------------------------------
# Thermodynamic helpers: saturation vapor pressures, latent heats, Clausius-
# Clapeyron integration. All values APPROX/EMPIRICAL (see docs/science/THERMODYNAMICS.md).
#
# Model, explicitly documented:
#   * Vapor pressure over the solid below the triple point:
#       ln(P) = ln(P_triple) - (h_sub / R) * (1/T - 1/T_triple)      (constant h_sub)
#   * Vapor pressure over the liquid above the triple point: two-anchor
#     integration shaped like a Watson correlation (power 0.38) fitted to
#     (P_triple, T_triple) and (P_crit, T_crit):
#       ln(P(T)) = ln(P_triple) + (ln(P_crit) - ln(P_triple)) * I(T) / I(T_crit)
#       I(T) = integral_{T_triple}^{T} ((T_crit - t)/(T_crit - T_triple))^0.38 / t^2 dt
#   * Melting: Clausius-Clapeyron linear approximation with per-species slope.
#
# Results are cached against quantized (species, T) and (species, P) keys so
# that repeated solver calls do not re-integrate.
# -----------------------------------------------------------------------------
class_name Thermodynamics
extends RefCounted

const WATSON_POWER := 0.38
const _T_BUCKET := 0.5            # K
static var _SAT_CACHE := {}       # "sym|Tbucket" -> ln(P)
static var _MELT_CACHE := {}      # "sym|Pbucket" -> T melt
static var _VAP_CACHE := {}       # "sym|Pbucket" -> T vapor

static func clear_cache() -> void:
	_SAT_CACHE.clear()
	_MELT_CACHE.clear()
	_VAP_CACHE.clear()

## Saturation vapor pressure (Pa) over the *solid* below the triple point.
## Returns null when the species has no triple point.
static func saturation_vapor_pressure_solid(sym: String, temperature_k: float) -> float:
	var d := SpeciesDatabase.get_species(sym)
	if d["t_triple"] == null:
		return -1.0
	var t := maxf(temperature_k, SciConstants.MIN_TEMPERATURE_K)
	var key := "%s|%.0f" % [sym, t / _T_BUCKET]
	if _SAT_CACHE.has(key):
		return exp(_SAT_CACHE[key])
	var p_ref: float = d["p_triple"]
	var t_ref: float = d["t_triple"]
	var h_sub: float = d["h_sub"]
	var lnp := log(p_ref) + (h_sub / SciConstants.R_u) * (1.0 / t_ref - 1.0 / t)
	_SAT_CACHE[key] = lnp
	return exp(lnp)

## Watson-shaped liquid vapor pressure anchored at triple & critical points.
static func saturation_vapor_pressure_liquid(sym: String, temperature_k: float) -> float:
	var d := SpeciesDatabase.get_species(sym)
	if d["t_triple"] == null or d["t_crit"] == null:
		return -1.0
	var t := clampf(temperature_k, d["t_triple"], minf(d["t_crit"], 0.999 * d["t_crit"]))
	var key := "%s|%.0f" % [sym, t / _T_BUCKET]
	if _SAT_CACHE.has(key):
		return exp(_SAT_CACHE[key])
	var i_t := _watson_integral(sym, t)
	var i_c := _watson_integral(sym, d["t_crit"])
	var lnp := log(SpeciesDatabase.triple_pressure(sym)) \
		+ (log(SpeciesDatabase.critical_pressure(sym)) - log(SpeciesDatabase.triple_pressure(sym))) * (i_t / maxf(i_c, 1e-12))
	_SAT_CACHE[key] = lnp
	return exp(lnp)

static func _watson_integral(sym: String, t: float) -> float:
	var d := SpeciesDatabase.get_species(sym)
	var t0: float = d["t_triple"]
	var tc: float = d["t_crit"]
	if t <= t0:
		return 0.0
	var n := 48
	var h := (t - t0) / n
	var s := 0.0
	var prev := _w_integrand(sym, t0)
	for i in range(1, n + 1):
		var tt := t0 + h * i
		var cur := _w_integrand(sym, tt)
		s += 0.5 * (prev + cur) * h
		prev = cur
	return s

static func _w_integrand(sym: String, t: float) -> float:
	var d := SpeciesDatabase.get_species(sym)
	var tc: float = d["t_crit"]
	var t0: float = d["t_triple"]
	var x := clampf((tc - t) / maxf(tc - t0, 1e-12), 0.0, 1.0)
	return pow(x, WATSON_POWER) / (t * t)

## Melting temperature (K) at a given pressure (linear Clapeyron approx).
static func melting_temperature(sym: String, pressure_pa: float) -> float:
	var d := SpeciesDatabase.get_species(sym)
	if d["t_triple"] == null:
		return -1.0
	var key := "%s|%.0f" % [sym, pressure_pa / _T_BUCKET]
	if _MELT_CACHE.has(key):
		return _MELT_CACHE[key]
	var t: float = d["t_triple"]
	var p_ref: float = d["p_triple"]
	var slope: float = d["melting_slope"]
	if p_ref > 0.0:
		t += slope * (pressure_pa - p_ref)
	_MELT_CACHE[key] = t
	return t

## Vaporization temperature (K) at a given pressure (inverse saturation curve).
static func vaporization_temperature(sym: String, pressure_pa: float) -> float:
	var d := SpeciesDatabase.get_species(sym)
	if d["t_triple"] == null or d["t_crit"] == null:
		return -1.0
	var key := "%s|%.0f" % [sym, pressure_pa / _T_BUCKET]
	if _VAP_CACHE.has(key):
		return _VAP_CACHE[key]
	var lo: float = d["t_triple"]
	var hi: float = d["t_crit"]
	# Walk up until pressure curve exceeds target.
	var t: float = d["t_triple"]
	var guard := 0
	while saturation_vapor_pressure_liquid(sym, t) < pressure_pa and guard < 400:
		t = minf(t + 0.5, d["t_crit"])
		guard += 1
	if guard >= 400:
		_VAP_CACHE[key] = d["t_crit"]
		return d["t_crit"]
	# Bisection for accurate root.
	lo = d["t_triple"]
	hi = t
	for i in range(48):
		var mid: float = 0.5 * (lo + hi)
		if saturation_vapor_pressure_liquid(sym, mid) < pressure_pa:
			lo = mid
		else:
			hi = mid
	_VAP_CACHE[key] = 0.5 * (lo + hi)
	return _VAP_CACHE[key]

## Sublimation temperature (K) at a given pressure below the triple point.
static func sublimation_temperature(sym: String, pressure_pa: float) -> float:
	var d := SpeciesDatabase.get_species(sym)
	if d["t_triple"] == null:
		return -1.0
	var p_ref: float = d["p_triple"]
	var t_ref: float = d["t_triple"]
	var h_sub: float = d["h_sub"]
	# ln(P) = ln(P_ref) + (h_sub/R)(1/t_ref - 1/T)  -> solve for T
	var t_inv := 1.0 / t_ref - (SciConstants.R_u / h_sub) * log(pressure_pa / maxf(p_ref, 1e-30))
	if t_inv <= 0.0:
		return 1e9
	return 1.0 / t_inv

## Molar latent heat available at the current temperature/phase (J/mol).
static func latent_heat(sym: String, phase: String, temperature_k: float) -> float:
	var d := SpeciesDatabase.get_species(sym)
	if phase == "solid_to_liquid":
		return d["h_fus"]
	if phase == "liquid_to_vapor":
		return _latent_vaporization(sym, temperature_k)
	if phase == "solid_to_vapor":
		return d["h_sub"]
	return 0.0

static func _latent_vaporization(sym: String, temperature_k: float) -> float:
	var d := SpeciesDatabase.get_species(sym)
	if d["t_crit"] == null:
		return d["h_vap"]
	var tc: float = d["t_crit"]
	var t0: float = d["t_triple"]
	var x := clampf((tc - temperature_k) / maxf(tc - t0, 1e-12), 0.0, 1.0)
	return d["h_vap"] * pow(x, WATSON_POWER)

## Heat capacity (J mol^-1 K^-1) rough ideal-gas approximation (per species).
static func gas_molar_cp(sym: String) -> float:
	match sym:
		"H2": return 28.8
		"He": return 20.8
		"N2": return 29.1
		"CO2": return 37.1
		"CO": return 29.1
		"H2O": return 33.6
		"CH4": return 35.7
		"NH3": return 35.1
		"SO2": return 39.9
		"O2": return 29.4
		"Ar": return 20.8
	return 29.0