# substrate_state.gd
# Ground/substrate state. All quantities use SI units unless stated otherwise.
class_name SubstrateState
extends RefCounted

var bedrock_minerals: Array = []       # [{name, fraction, conf}]
var elemental_mass_fraction := {}      # kg element / kg rock
var normative_notes: Array = []
var residue := {}
var crust_style := "felsic"
var fidelity := SciConstants.FIDELITY_SIMPLIFIED_PHYSICAL

# Geometry / texture.
var regolith_thickness := 0.0          # m
var porosity := 0.35                   # void fraction
var grain_size_mean_m := 0.001         # geometric-mean grain diameter
var grain_size_sigma := 2.0            # geometric spread, dimensionless
var permeability_m2 := 1.0e-12         # intrinsic permeability
var roughness_rms_m := 0.02            # local micro-relief RMS

# Composition/alteration indices (0..1).
var volatile_fraction := 0.0
var moisture_fraction := 0.0
var oxidation_index := 0.0
var hydration_index := 0.0
var organic_fraction := 0.0
var weathering_index := 0.0
var age_years := 0.0

# Mechanical / thermal.
var density := 2800.0                  # grain density kg m^-3
var bulk_density := 1820.0             # porous bulk density kg m^-3
var thermal_conductivity := 2.2        # W m^-1 K^-1
var heat_capacity := 1090.0            # J kg^-1 K^-1
var thermal_diffusivity := 0.0         # m^2 s^-1
var hardness_mohs_approx := 5.5
var albedo := 0.20
var emissivity := 0.92

func recompute_thermophysical() -> void:
	porosity = clampf(porosity, 0.0, 0.9)
	bulk_density = maxf(1.0, density * (1.0 - porosity))
	thermal_diffusivity = thermal_conductivity / maxf(bulk_density * heat_capacity, 1.0)
	# Kozeny-Carman style permeability estimate. This is an empirical approximation,
	# but it ties permeability to the actual grain size and porosity rather than a
	# free random number.
	var phi := clampf(porosity, 1.0e-4, 0.89)
	var d := maxf(grain_size_mean_m, 1.0e-8)
	permeability_m2 = d * d * pow(phi, 3.0) / maxf(180.0 * pow(1.0 - phi, 2.0), 1.0e-12)

func dominant_mineral() -> String:
	if bedrock_minerals.is_empty():
		return "unallocated"
	return bedrock_minerals[0].get("name", "unallocated")

func describe() -> String:
	return "bedrock ~ %s, regolith %.2f m, phi=%.2f, grain=%.3g m, %d phases" % [
		dominant_mineral(), regolith_thickness, porosity, grain_size_mean_m, bedrock_minerals.size()
	]
