# substrate_state.gd
# -----------------------------------------------------------------------------
# Describes the solid ground beneath the surface: bedrock mineralogy (from the
# normative allocation), regolith cover, thermophysical properties, and the
# elemental rock budget that produced it.
# -----------------------------------------------------------------------------
class_name SubstrateState
extends RefCounted

var bedrock_minerals: Array = []       # [{name, fraction, conf}]
var elemental_mass_fraction := {}      # symbol -> kg element / kg rock
var normative_notes: Array = []        # allocation flags
var residue := {}                      # unconsumed elements, kg / kg rock
var regolith_thickness := 0.0          # m
var porosity := 0.35
var density := 2800.0                  # kg m^-3 (bulk)
var thermal_conductivity := 2.2        # W m^-1 K^-1
var heat_capacity := 1090.0            # J kg^-1 K^-1
var thermal_diffusivity := 0.0         # m^2 s^-1 (derived k/(rho*cp))
var crust_style := "felsic"
var fidelity := SciConstants.FIDELITY_SIMPLIFIED_PHYSICAL

func recompute_thermophysical() -> void:
	var cp := maxf(heat_capacity, 1.0)
	var den := maxf(density, 1.0)
	thermal_diffusivity = thermal_conductivity / (den * cp)

func dominant_mineral() -> String:
	if bedrock_minerals.is_empty():
		return "unallocated"
	return bedrock_minerals[0]["name"]

func describe() -> String:
	var d := dominant_mineral()
	return "bedrock ~ %s, regolith %.2f m, %d phases" % [d, regolith_thickness, bedrock_minerals.size()]