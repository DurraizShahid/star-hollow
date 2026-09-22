# sediment_model.gd
# -----------------------------------------------------------------------------
# Detrital sediment: erosion supplies material on slopes, deposition fills
# basins. Purely a function of boundary conditions (elevation, slope, wind),
# so it is continuous across chunk borders and deterministic.
#
# The model is statistical (cover fractions + grain-size flavour), NOT a full
# hydraulic transport grid; sediment budget is documented as qualitative.
# -----------------------------------------------------------------------------
class_name SedimentModel
extends RefCounted

## Returns { cover: 0..1, kind: "gravel"|"sand"|"silt"|"clay"|"dune", notes }
static func cover(boundary: GeologyModel.CellBoundary, weathering: Dictionary, hot: bool) -> Dictionary:
	var elev := boundary.elevation
	var slope := boundary.slope
	var wind := boundary.wind_speed
	var supply := clampf((0.2 + 2.2 * pow(slope, 0.7)) * wind, 0.0, 1.0)

	# Basins (low elevation) accumulate; high slopes shed.
	var deposition_bias := clampf(1.0 - elev / 4000.0, 0.0, 1.2)
	var cover := clampf(supply * 0.4 + deposition_bias * 0.35 - slope * 0.5, 0.0, 1.0)

	var kind := "sand"
	var notes: Array = []
	if wind > 1.3 and cover > 0.4 and hot:
		kind = "dune"
		notes.append("aeolian forms")
	elif slope > 0.25:
		kind = "gravel"
		notes.append("slope talus")
	elif deposition_bias > 0.75 and cover > 0.5:
		kind = "silt"
		notes.append("basin fill")
	elif weathering.get("secondary", []).has("Kaolinite Al2Si2O5(OH)4"):
		kind = "clay"
		notes.append("chemogenic mud")
	return { "cover": cover, "kind": kind, "notes": notes }