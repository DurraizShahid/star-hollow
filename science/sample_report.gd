# sample_report.gd
# -----------------------------------------------------------------------------
# Builds the scientific sample report for one cell from the fully-solved state.
# The report is pure data (many fields from the coupled solver's cell record);
# UI formatting happens in the game layer, not here.
# -----------------------------------------------------------------------------
class_name SampleReport
extends RefCounted

## Build a report dictionary for one solved cell.
## cell: the record produced by CoupledPlanetSolver.generate_chunk.
static func build(cell: Dictionary, planet: PlanetParameters, solver, position: Vector2) -> Dictionary:
	var substrate: SubstrateState = cell.get("substrate")
	var surface: SurfaceState = cell.get("surface")
	var thermal: ThermalState = cell.get("thermal")
	var atm = cell.get("atmosphere")
	var classify: Dictionary = cell.get("classification", {})

	var elements := {}
	var budget: Dictionary = substrate.elemental_mass_fraction
	# Report in mass percent sorted descending.
	var ekeys := budget.keys()
	ekeys.sort_custom(func(a, b): return budget[a] > budget[b])
	for e in ekeys:
		elements[e] = budget[e] * 100.0

	var minerals := []
	var top5: Dictionary = {}
	for min in substrate.bedrock_minerals:
		minerals.append({ "name": min["name"], "fraction": min.get("fraction", 0.0) })
		if top5.size() < 5:
			top5[min["name"]] = min.get("fraction", 0.0)

	var species := []
	for s in atm.species:
		species.append({ "symbol": s, "mole_frac": atm.mole_fractions[s] })

	return {
		"position": position,
		"x": position.x, "y": position.y,
		"classification": classify.get("label", ""),
		"kind": classify.get("kind", ""),
		"short": classify.get("short", ""),
		"temperature": thermal.temperature,
		"substrate_temperature": thermal.substrate_temperature,
		"pressure": atm.total_pressure,
		"density": atm.density,
		"gravity": planet.surface_gravity,
		"surface": {
			"name": classify.get("label", ""),
			"albedo": surface.albedo,
			"roughness": surface.roughness,
			"covers": {
				"rock": 1.0 - surface.sediment_cover,
				"sediment": surface.sediment_cover,
				"liquid": surface.liquid_cover,
				"frost": surface.frost_cover,
				"organic": surface.organic_cover,
			},
			"materials": classify.get("materials", []),
		},
		"substrate": {
			"regolith_m": substrate.regolith_thickness,
			"porosity": substrate.porosity,
			"density": substrate.density,
			"k": substrate.thermal_conductivity,
			"cp": substrate.heat_capacity,
			"crust": substrate.crust_style,
			"minerals": minerals,
		},
		"elements": elements,
		"atmosphere": {
			"species": species,
			"scale_height_m": atm.scale_height,
			"tau_ir": atm.greenhouse_tau,
			"notes": atm.notes,
		},
		"energy": thermal.energies(),
		"biosphere": cell.get("biosphere", {}),
		"model": {
			"version": SciConstants.WORLD_GENERATOR_VERSION,
			"seed": planet.seed,
			"preset": planet.preset if planet.preset != "" else "random",
			"fidelity": {
				"thermal": SciConstants.FIDELITY_NAME.get(SciConstants.FIDELITY_SIMPLIFIED_PHYSICAL, "simplified"),
				"atmosphere": SciConstants.FIDELITY_NAME.get(SciConstants.FIDELITY_HEURISTIC, "heuristic"),
				"minerals": SciConstants.FIDELITY_NAME.get(SciConstants.FIDELITY_SIMPLIFIED_PHYSICAL, "simplified"),
			},
			"convergence": thermal.convergence,
			"iterations": thermal.iterations,
		},
	}