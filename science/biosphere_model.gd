# biosphere_model.gd
# -----------------------------------------------------------------------------
# Can-life-exist and what-thrives: a per-cell suitability function of
#   * usable energy flux (daylight + geothermal),
#   * temperature window,
#   * liquid water (or other polar solvent) stability,
#   * atmospheric density (transport / shielding).
#
# Outputs:
#   biomass        kg m^-2
#   organic_cover  0..1 (biogenic soil / tholin)
#   biome_label    descriptive
#   energy, hab, liquid factors (for the report)
#
# Two extreme regimes included for cold worlds: photochemical tholin haze on
# Titan-like surfaces is NOT biology -- it is still called "organics" only in
# the material catalogue (documented distinction).
# -----------------------------------------------------------------------------
class_name BiosphereModel
extends RefCounted

static func assess(thermal: ThermalState, surface: SurfaceState, atm: AtmosphereState,
		boundary: GeologyModel.CellBoundary, planet: PlanetParameters) -> Dictionary:
	var t := thermal.temperature
	var energy := thermal.absorbed_solar + thermal.geothermal * 0.35

	var habitability := 0.0
	if t >= 250.0 and t <= 340.0:
		habitability = 1.0 - clampf(absf(t - 288.0) / 90.0, 0.0, 0.85)
	var liquid_like := surface.has_liquid_or_frost("H2O") or surface.has_liquid_or_frost("H2O")
	var liquid_factor := 0.5 if (surface.liquid_cover >= 0.02 and surface.liquid_species == "H2O") else 0.0

	var atm_density_factor := clampf(log(maxf(atm.total_pressure, 1.0) * atm.density * 0.2 + 1.0) / 6.0, 0.0, 1.0)

	var hab := clampf(habitability * (0.4 + 0.6 * liquid_factor) * (0.3 + 0.7 * atm_density_factor), 0.0, 1.0)

	var biomass := 0.0
	var organic := 0.0
	var label := "sterile"
	var notes: Array = []

	# Photochemical tholin on cold worlds (abiotic).
	if t < 160.0 and atm.partial_pressure("CH4") > 100.0:
		organic = clampf(0.05 + atm.partial_pressure("CH4") / 4.0e4, 0.0, 0.6)
		label = "tholin (abiotic organics)"
		notes.append("photochemical haze deposit")

	# Habitability does not imply inhabitance. Biology is only instantiated when
	# the planet explicitly carries a biosphere; abiotic tholins above remain possible.
	if planet.biosphere_enabled and energy > 8.0 and hab > 0.015 and surface.liquid_cover >= 0.01 and surface.has_liquid_or_frost("H2O"):
		var growth := clampf((energy - 8.0) / 60.0, 0.0, 1.0) * hab * liquid_factor * 3.0
		biomass = clampf(growth, 0.0, 2.4)
		organic = minf(1.0, 0.1 + biomass * 0.22)
		if biomass < 0.02:
			label = "pioneering chemotrophs"
			notes.append("geothermal + water niche")
		elif biomass < 0.4:
			label = "scattered photosynthetic colonies"
		else:
			label = "dense biogenic mat"
	elif planet.biosphere_enabled and energy > 4.0 and surface.has_liquid_or_frost("H2O") and hab > 0.004:
		biomass = 0.02
		organic = 0.04
		label = "marginal thermosynthetic niche"
		notes.append("low energy")

	return {
		"biomass": biomass, "organic_cover": organic, "label": label,
		"habitability": hab, "energy": energy, "liquid_factor": liquid_factor,
		"atm_factor": atm_density_factor,
		"notes": notes,
	}