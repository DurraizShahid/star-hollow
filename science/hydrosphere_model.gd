# hydrosphere_model.gd
# Planet-scale condensed volatile reservoir projected onto local topography.
# This is a volume-conserving statistical sea-level model over a deterministic
# representative elevation sample; it is not a full hydraulic flow solver.
class_name HydrosphereModel
extends RefCounted

const SAMPLE_HALF_WIDTH := 8
const SAMPLE_SPACING_M := 24000.0
const MIN_EQUIVALENT_DEPTH_M := 0.001

var planet: PlanetParameters
var geology: GeologyModel
var atmosphere: AtmosphereState
var mean_equivalent_depth_m := {} # species -> planet-mean depth if spread globally
var sea_levels_m := {}            # species -> solved equipotential elevation

func _init(p: PlanetParameters, g: GeologyModel, atm: AtmosphereState) -> void:
	planet = p
	geology = g
	atmosphere = atm
	_build_levels()

func _build_levels() -> void:
	var elevations: Array[float] = []
	for iy in range(-SAMPLE_HALF_WIDTH, SAMPLE_HALF_WIDTH + 1):
		for ix in range(-SAMPLE_HALF_WIDTH, SAMPLE_HALF_WIDTH + 1):
			var x := float(ix) * SAMPLE_SPACING_M
			var y := float(iy) * SAMPLE_SPACING_M
			elevations.append(geology.boundary_at(x, y).elevation)
	if elevations.is_empty():
		return
	for s in atmosphere.condensed_reservoir_column_mass.keys():
		if not SpeciesDatabase.has(s) or not SpeciesDatabase.is_condensable(s):
			continue
		var rho_variant: Variant = SpeciesDatabase.liquid_density(s)
		if rho_variant == null or float(rho_variant) <= 0.0:
			rho_variant = SpeciesDatabase.solid_density(s)
		if rho_variant == null or float(rho_variant) <= 0.0:
			continue
		var rho := float(rho_variant)
		var column_mass := float(atmosphere.condensed_reservoir_column_mass.get(s, 0.0))
		var mean_depth := column_mass / rho
		if mean_depth < MIN_EQUIVALENT_DEPTH_M:
			continue
		mean_equivalent_depth_m[s] = mean_depth
		sea_levels_m[s] = _solve_level(elevations, mean_depth)

func _solve_level(elevations: Array[float], target_mean_depth: float) -> float:
	var min_elev: float = elevations.min()
	var max_elev: float = elevations.max()
	var lo := min_elev - 1.0
	var hi := max_elev + target_mean_depth * 2.0 + 1.0
	for _i in range(64):
		var mid := 0.5 * (lo + hi)
		var depth_sum := 0.0
		for e in elevations:
			depth_sum += maxf(mid - e, 0.0)
		var mean_depth := depth_sum / float(elevations.size())
		if mean_depth < target_mean_depth:
			lo = mid
		else:
			hi = mid
	return 0.5 * (lo + hi)

func state_at(elevation_m: float, temperature_k: float, local_atm: AtmosphereState) -> Dictionary:
	var best := {
		"species": "",
		"phase": PhaseSolver.PHASE_VAPOR,
		"depth_m": 0.0,
		"cover": 0.0,
		"water_table_depth_m": INF,
		"mean_equivalent_depth_m": 0.0,
	}
	var shallowest_table := INF
	for s in sea_levels_m.keys():
		var level := float(sea_levels_m[s])
		shallowest_table = minf(shallowest_table, maxf(elevation_m - level, 0.0))
		var local_depth := maxf(level - elevation_m, 0.0)
		if local_depth <= 0.0:
			continue
		# Total ambient pressure decides whether a bulk condensed reservoir can
		# remain liquid/solid; vapor partial pressure is handled separately by
		# the atmospheric condensation solver.
		var phase_info := PhaseSolver.phase_of(s, temperature_k, local_atm.total_pressure)
		var phase := String(phase_info.get("phase", PhaseSolver.PHASE_VAPOR))
		if phase not in [PhaseSolver.PHASE_LIQUID, PhaseSolver.PHASE_SOLID]:
			continue
		if local_depth <= float(best["depth_m"]):
			continue
		best = {
			"species": s,
			"phase": phase,
			"depth_m": local_depth,
			"cover": clampf(local_depth / 0.5, 0.0, 1.0),
			"water_table_depth_m": 0.0,
			"mean_equivalent_depth_m": float(mean_equivalent_depth_m.get(s, 0.0)),
		}
	if String(best["species"]) == "":
		best["water_table_depth_m"] = shallowest_table
	return best
