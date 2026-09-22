# atmospheric_escape.gd
# Long-timescale atmospheric retention approximation.
#
# This is NOT a full upper-atmosphere or hydrodynamic escape model. It uses the
# dimensionless Jeans escape parameter at an estimated exobase temperature:
#
#   lambda = m g R / (k_B T_exo) = M g R / (R_u T_exo)
#
# where M is molar mass. Low lambda species are progressively depleted with age.
# The mapping from lambda+age to retained fraction is empirical and is surfaced
# as heuristic fidelity in the probe/docs.
class_name AtmosphericEscape
extends RefCounted

const LAMBDA_LOSS_CENTER := 18.0
const LAMBDA_TRANSITION_WIDTH := 4.0

static func estimated_exobase_temperature(planet: PlanetParameters) -> float:
	# Stellar heating proxy. Hot/high-flux bodies get hotter upper atmospheres.
	var flux_ratio := maxf(planet.stellar_flux / SciConstants.SOLAR_FLUX_EARTH, 1.0e-6)
	var radiative := 700.0 * pow(flux_ratio, 0.22)
	var stellar_uv_proxy := clampf(planet.stellar_effective_temperature / 5772.0, 0.45, 1.5)
	return clampf(radiative * stellar_uv_proxy, 80.0, 3500.0)

static func jeans_parameter(planet: PlanetParameters, sym: String) -> float:
	if not SpeciesDatabase.has(sym):
		return INF
	var t_exo := estimated_exobase_temperature(planet)
	var molar_mass := SpeciesDatabase.molar_mass(sym)
	return molar_mass * planet.surface_gravity * planet.radius / (SciConstants.R_u * t_exo)

static func retention_fraction(planet: PlanetParameters, sym: String) -> float:
	var lambda := jeans_parameter(planet, sym)
	if not is_finite(lambda):
		return 1.0
	# Logistic transition: strongly bound gases retained, low-lambda gases lost.
	var instantaneous := 1.0 / (1.0 + exp(-(lambda - LAMBDA_LOSS_CENTER) / LAMBDA_TRANSITION_WIDTH))
	# Older systems have had more time to deplete marginally retained species.
	var age_gyr := clampf(planet.age / 1.0e9, 0.0, 14.0)
	var exposure := clampf(age_gyr / 4.5, 0.05, 3.0)
	return clampf(pow(instantaneous, exposure), 0.0, 1.0)

static func report(planet: PlanetParameters, species: Array) -> Dictionary:
	var out := {}
	for sym in species:
		if not SpeciesDatabase.has(String(sym)):
			continue
		out[String(sym)] = {
			"jeans_parameter": jeans_parameter(planet, String(sym)),
			"retained_fraction": retention_fraction(planet, String(sym)),
			"exobase_temperature_k": estimated_exobase_temperature(planet),
			"fidelity": SciConstants.FIDELITY_HEURISTIC,
		}
	return out
