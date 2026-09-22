# weathering_model.gd
# -----------------------------------------------------------------------------
# Weathering / regolith production as a deterministic function of climate and
# substrate. Pure per-cell functions of state => spatially continuous.
#
# Regolith production:
#   physical  : proportional to slope^0.6, wind, and freeze-thaw cycling
#   chemical  : only when liquid water is/was present; temperature drives rate;
#               produces clay/oxide/hydrated-salt secondary minerals.
# Carbonation: atmospheric CO2 can attack Ca-bearing minerals when wet, moving
# some rock-bound Ca into carbonates (calcite) -- a trace flux, documented.
# -----------------------------------------------------------------------------
class_name WeatheringModel
extends RefCounted

const SECONDARY_TEMPLATES := {
	"Kaolinite Al2Si2O5(OH)4": { "alpha": 100.0, "molar": 258.16 },
	"Hematite Fe2O3": { "alpha": 1.0, "molar": 159.69 },
	"Calcite CaCO3": { "alpha": 2.0, "molar": 100.09 },
}

## Returns { thick: m, secondary: [mineral names], notes }
static func regolith(surface: SurfaceState, substrate: SubstrateState,
		thermal: ThermalState, boundary: GeologyModel.CellBoundary, atm: AtmosphereState) -> Dictionary:
	var t := thermal.temperature
	var slope := boundary.slope
	var wind := boundary.wind_speed

	var has_water := _wet_surface(surface)
	var freeze_cycles := (1.0 - clampf(absf(t - 273.15) / 160.0, 0.0, 1.0)) if surface.has_liquid_or_frost("H2O") else 0.0

	# Physical erosion rate.
	var physical := 0.0015 + 0.02 * pow(slope, 0.6) + 0.004 * wind + 0.12 * freeze_cycles
	# Chemical weathering rate (Arrhenius-like on liquid-water activity).
	var wtemp := maxf(0.0, t - 250.0)
	var chemical := 0.0
	var chem_index := 0.0
	if has_water:
		chem_index = maxf(wtemp / 40.0, freeze_cycles * 0.3)
		chemical = 0.06 * chem_index * chem_index
	var thick := clampf((physical + chemical) * 60.0, 0.02, 120.0)

	# Secondary mineral set from chemical weathering intensity.
	var secondary: Array = []
	if chem_index > 0.15:
		var aces := substrate.dominant_mineral()
		if aces.contains("Feldspar") or aces.contains("Anorthite") or aces.contains("Corundum"):
			secondary.append("Kaolinite Al2Si2O5(OH)4")
		if substrate.residue.get("Fe", 0.0) > 1.0e-4 or substrate.dominant_mineral().contains("Olivine"):
			secondary.append("Hematite Fe2O3")
		if atm.partial_pressure("CO2") > 300.0 and substrate.residue.get("Ca", 0.0) > 1.0e-4:
			secondary.append("Calcite CaCO3")

	var notes: Array = []
	if has_water:
		notes.append("liquid-water weathering")
	elif freeze_cycles > 0.3:
		notes.append("freeze-thaw dominant")
	return { "thick": thick, "secondary": secondary.duplicate(), "notes": notes }

static func _wet_surface(surface: SurfaceState) -> bool:
	return surface.liquid_cover >= 0.02 and surface.liquid_species == "H2O"