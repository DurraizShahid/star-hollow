# surface_state.gd
# Resolved layer immediately above the substrate: sediment, clasts, condensates,
# liquids, organics and vegetation. Renderer consumes this state; it never owns it.
class_name SurfaceState
extends RefCounted

var materials: Array = []
var dominant_label := "bare_rock"
var dominant_kind := "rock"

var rock_visible := true
var sediment_cover := 0.0
var sediment_kind := ""
var rock_cover := 0.0
var boulder_cover := 0.0
var pebble_cover := 0.0
var dust_cover := 0.0
var salt_cover := 0.0
var liquid_cover := 0.0
var liquid_species := ""
var liquid_depth_m := 0.0
var frost_cover := 0.0
var frost_species := ""
var frost_equivalent_depth_m := 0.0
var water_table_depth_m := INF
var organic_cover := 0.0
var vegetation_cover := 0.0
var vegetation_style := ""

var base_albedo := 0.2
var base_emissivity := 0.92
var base_roughness := 0.4
var albedo := 0.2
var emissivity := 0.92
var roughness := 0.4
var relief := 0.0
var humidity := 0.0
var volatile_reservoir := {}           # species -> kg m^-2
var phase_notes: Array = []
var confidence := SciConstants.FIDELITY_SIMPLIFIED_PHYSICAL

func dominant_surface_label() -> String:
	return dominant_label

func has_liquid_or_frost(sym: String) -> bool:
	return (liquid_cover >= 0.02 and liquid_species == sym) \
		or (frost_cover >= 0.02 and frost_species == sym)

func normalize_covers() -> void:
	sediment_cover = clampf(sediment_cover, 0.0, 1.0)
	rock_cover = clampf(rock_cover, 0.0, 1.0)
	boulder_cover = clampf(boulder_cover, 0.0, 1.0)
	pebble_cover = clampf(pebble_cover, 0.0, 1.0)
	dust_cover = clampf(dust_cover, 0.0, 1.0)
	salt_cover = clampf(salt_cover, 0.0, 1.0)
	liquid_cover = clampf(liquid_cover, 0.0, 1.0)
	frost_cover = clampf(frost_cover, 0.0, 1.0)
	organic_cover = clampf(organic_cover, 0.0, 1.0)
	vegetation_cover = clampf(vegetation_cover, 0.0, 1.0)
