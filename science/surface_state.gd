# surface_state.gd
# -----------------------------------------------------------------------------
# The resolved surface of a cell: what is actually exposed (rock, sediment,
# ices, liquid), its radiative properties, volatile content, and the humidity
# regime. This is the object the renderer turns into colour.
# -----------------------------------------------------------------------------
class_name SurfaceState
extends RefCounted

var materials: Array = []              # [{label, fraction, kind}]  kind in material_classifier kinds
var dominant_label := "bare_rock"
var dominant_kind := "rock"

var rock_visible := true
var sediment_cover := 0.0              # 0..1
var liquid_cover := 0.0                # 0..1 (ocean/lake under liquid)
var liquid_species := ""               # e.g. "H2O", "CH4", ""
var frost_cover := 0.0                 # 0..1
var frost_species := ""                # e.g. "CO2", "H2O", "CH4", "SO2", ""
var organic_cover := 0.0               # 0..1 (tholin/soil organisms)

var albedo := 0.2
var emissivity := 0.92
var roughness := 0.4                   # 0 (flat) .. 1 (rugged)
var relief := 0.0
var humidity := 0.0                    # 0..1 relative humidity (of main volatile)
var volatile_reservoir := {}           # symbol -> kg m^-2 condensed at surface

var phase_notes: Array = []
var confidence := SciConstants.FIDELITY_SIMPLIFIED_PHYSICAL

func dominant_surface_label() -> String:
	return dominant_label

## Whether this surface exposes liquid or frost of a given volatile species.
func has_liquid_or_frost(sym: String) -> bool:
	return (liquid_cover >= 0.02 and liquid_species == sym) \
		or (frost_cover >= 0.02 and frost_species == sym)