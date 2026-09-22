# sample_report.gd
# Immutable-style report packet assembled from the solved cell state.
class_name SampleReport
extends RefCounted

static func build(cell: Dictionary, planet: PlanetParameters, solver, position: Vector2) -> Dictionary:
	var substrate: SubstrateState = cell.get("substrate")
	var surface: SurfaceState = cell.get("surface")
	var thermal: ThermalState = cell.get("thermal")
	var atm: AtmosphereState = cell.get("atmosphere")
	var classify: Dictionary = cell.get("classification", {})
	var boundary: GeologyModel.CellBoundary = cell.get("boundary")

	var elements_mass_pct := {}
	var mole_raw := {}
	var mole_total := 0.0
	for e in substrate.elemental_mass_fraction.keys():
		var f: float = substrate.elemental_mass_fraction[e]
		elements_mass_pct[e] = f * 100.0
		if ElementDatabase.has_symbol(e):
			var mol := f / maxf(ElementDatabase.mass_kg_per_mol(e), 1.0e-12)
			mole_raw[e] = mol
			mole_total += mol
	var elements_mole_pct := {}
	for e in mole_raw.keys():
		elements_mole_pct[e] = 100.0 * mole_raw[e] / maxf(mole_total, 1.0e-12)

	var minerals: Array = []
	for m in substrate.bedrock_minerals:
		minerals.append({
			"name": m.get("name", "?"),
			"fraction": float(m.get("fraction", 0.0)),
			"mass_pct": float(m.get("fraction", 0.0)) * 100.0,
			"confidence": m.get("conf", "normative"),
		})

	var species: Array = []
	for s in atm.species:
		species.append({
			"symbol": s,
			"name": SpeciesDatabase.pretty_name(s),
			"mole_frac": atm.mole_fraction(s),
			"mole_pct": atm.mole_fraction(s) * 100.0,
			"partial_pressure_pa": atm.partial_pressure(s),
			"phase_at_surface": PhaseSolver.phase_of(s, thermal.temperature, atm.partial_pressure(s)).get("phase", "unknown")
				if SpeciesDatabase.is_condensable(s) else "gas",
		})

	var phase_fractions := {
		"solid": clampf(1.0 - maxf(surface.liquid_cover, surface.frost_cover), 0.0, 1.0),
		"liquid": surface.liquid_cover,
		"frost_or_ice": surface.frost_cover,
	}

	return {
		"position": position,
		"x": position.x, "y": position.y,
		"classification": classify.get("label", ""),
		"kind": classify.get("kind", ""),
		"short": classify.get("short", ""),
		"temperature": thermal.temperature,
		"air_temperature": atm.temperature,
		"shallow_subsurface_temperature": thermal.shallow_subsurface_temperature,
		"substrate_temperature": thermal.substrate_temperature,
		"pressure": atm.total_pressure,
		"density": atm.density,
		"gravity": planet.surface_gravity,
		"elevation_m": boundary.elevation,
		"elements": elements_mass_pct, # compatibility alias
		"elements_mass_pct": elements_mass_pct,
		"elements_mole_pct": elements_mole_pct,
		"phase_fractions": phase_fractions,
		"surface": {
			"name": classify.get("label", ""),
			"albedo": surface.albedo,
			"emissivity": surface.emissivity,
			"roughness": surface.roughness,
			"humidity": surface.humidity,
			"liquid_species": surface.liquid_species,
			"liquid_depth_m": surface.liquid_depth_m,
			"frost_species": surface.frost_species,
			"frost_equivalent_depth_m": surface.frost_equivalent_depth_m,
			"water_table_depth_m": surface.water_table_depth_m,
			"covers": {
				"rock": surface.rock_cover,
				"boulder": surface.boulder_cover,
				"pebble": surface.pebble_cover,
				"dust": surface.dust_cover,
				"salt": surface.salt_cover,
				"sediment": surface.sediment_cover,
				"liquid": surface.liquid_cover,
				"frost": surface.frost_cover,
				"organic": surface.organic_cover,
				"vegetation": surface.vegetation_cover,
			},
			"sediment_kind": surface.sediment_kind,
			"vegetation_style": surface.vegetation_style,
			"materials": classify.get("materials", []),
			"phase_notes": surface.phase_notes.duplicate(),
		},
		"substrate": {
			"regolith_m": substrate.regolith_thickness,
			"porosity": substrate.porosity,
			"grain_density_kg_m3": substrate.density,
			"bulk_density_kg_m3": substrate.bulk_density,
			"grain_size_mean_m": substrate.grain_size_mean_m,
			"grain_size_sigma": substrate.grain_size_sigma,
			"permeability_m2": substrate.permeability_m2,
			"thermal_conductivity_w_mk": substrate.thermal_conductivity,
			"heat_capacity_j_kgk": substrate.heat_capacity,
			"thermal_diffusivity_m2_s": substrate.thermal_diffusivity,
			"hardness_mohs_approx": substrate.hardness_mohs_approx,
			"weathering_index": substrate.weathering_index,
			"oxidation_index": substrate.oxidation_index,
			"hydration_index": substrate.hydration_index,
			"moisture_fraction": substrate.moisture_fraction,
			"organic_fraction": substrate.organic_fraction,
			"age_years": substrate.age_years,
			"crust": substrate.crust_style,
			"minerals": minerals,
			"residue": substrate.residue.duplicate(),
			"notes": substrate.normative_notes.duplicate(),
		},
		"atmosphere": {
			"species": species,
			"mean_molar_mass_kg_mol": atm.mean_molar_mass,
			"scale_height_m": atm.scale_height,
			"tau_ir": atm.greenhouse_tau,
			"wind_m_s": atm.wind_speed_m_s,
			"wind_vector": atm.wind_vector,
			"relative_humidity": atm.relative_humidity,
			"reservoir_column_mass_kg_m2": atm.reservoir_column_mass.duplicate(true),
			"condensed_reservoir_column_mass_kg_m2": atm.condensed_reservoir_column_mass.duplicate(true),
			"escape_diagnostics": atm.escape_diagnostics.duplicate(true),
			"notes": atm.notes.duplicate(),
		},
		"energy": thermal.energies(),
		"biosphere": cell.get("biosphere", {}),
		"hydrosphere": {
			"mean_equivalent_depth_m": solver.hydrosphere.mean_equivalent_depth_m.duplicate(true),
			"sea_levels_m": solver.hydrosphere.sea_levels_m.duplicate(true),
		},
		"geology": {
			"province": boundary.province_primary,
			"secondary_province": boundary.province_secondary,
			"slope": boundary.slope,
			"fracture_density": boundary.fracture_density,
		},
		"model": {
			"version": SciConstants.WORLD_GENERATOR_VERSION,
			"seed": planet.seed,
			"preset": planet.preset if planet.preset != "" else "random",
			"fidelity": {
				"thermal": SciConstants.FIDELITY_NAME[SciConstants.FIDELITY_SIMPLIFIED_PHYSICAL],
				"atmosphere": SciConstants.FIDELITY_NAME[SciConstants.FIDELITY_SIMPLIFIED_PHYSICAL],
				"minerals": SciConstants.FIDELITY_NAME[SciConstants.FIDELITY_SIMPLIFIED_PHYSICAL],
			},
			"thermal_convergence": thermal.convergence,
			"thermal_iterations": thermal.iterations,
			"thermal_residual_w_m2": thermal.residual_w_m2,
			"thermal_converged": thermal.converged,
			"coupling": cell.get("coupling", {}),
			"confidence": {
				"orbital_gravity": SciConstants.FIDELITY_NAME[SciConstants.FIDELITY_REFERENCE],
				"local_pressure_density": SciConstants.FIDELITY_NAME[SciConstants.FIDELITY_SIMPLIFIED_PHYSICAL],
				"atmospheric_escape": SciConstants.FIDELITY_NAME[SciConstants.FIDELITY_HEURISTIC],
				"surface_temperature": SciConstants.FIDELITY_NAME[SciConstants.FIDELITY_SIMPLIFIED_PHYSICAL],
				"phase_boundaries": SciConstants.FIDELITY_NAME[SciConstants.FIDELITY_THERMODYNAMIC],
				"mineral_assemblage": "normative / stoichiometric; not Gibbs equilibrium",
				"hydrosphere_level": "volume-conserving statistical terrain approximation",
				"weathering_sediment": SciConstants.FIDELITY_NAME[SciConstants.FIDELITY_EMPIRICAL],
				"biosphere": SciConstants.FIDELITY_NAME[SciConstants.FIDELITY_HEURISTIC],
			},
			"approximation_flags": [
				"gray atmosphere",
				"normative mineral allocation (not full Gibbs minimization)",
				"single-column local atmosphere",
				"statistical sea-level / condensed-reservoir projection",
				"statistical sediment transport",
			],
		},
	}
