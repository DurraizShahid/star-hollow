# tests/run_tests.gd
# Focused numerical/physics assertions. Godot 4.7.2, headless-safe.
extends SceneTree

const PATHS := [
	"res://science/scientific_constants.gd",
	"res://science/element_database.gd",
	"res://science/species_database.gd",
	"res://science/mineral_database.gd",
	"res://science/planet_parameters.gd",
	"res://science/geology_provinces.gd",
	"res://science/geology_model.gd",
	"res://science/thermodynamics.gd",
	"res://science/phase_solver.gd",
	"res://science/atmosphere_state.gd",
	"res://science/atmosphere_model.gd",
	"res://science/thermal_state.gd",
	"res://science/thermal_model.gd",
	"res://science/substrate_state.gd",
	"res://science/surface_state.gd",
	"res://science/weathering_model.gd",
	"res://science/sediment_model.gd",
	"res://science/biosphere_model.gd",
	"res://science/equilibrium_solver.gd",
	"res://science/material_classifier.gd",
	"res://science/coupled_planet_solver.gd",
	"res://science/sample_report.gd",
	"res://science/discovery_system.gd",
]

var failures := 0
var asserts := 0

func _initialize() -> void:
	var guard := create_timer(180.0)
	guard.timeout.connect(quit.bind(2))
	for p in PATHS:
		var script := load(p)
		_check("loads %s" % p.get_file(), script != null)

	# Planetary mechanics / derived state.
	var earth := PlanetParameters.from_preset("earthlike", 1)
	_check("Earth gravity ~= 9.81 m/s2", absf(earth.surface_gravity - SciConstants.EARTH_GRAVITY) < 0.05)
	_check("Earth T_eq ~= 255 K", absf(earth.equilibrium_temperature - 255.0) < 2.0)
	var mars := PlanetParameters.from_preset("marslike", 1)
	var titan := PlanetParameters.from_preset("titanlike", 1)
	var pluto := PlanetParameters.from_preset("plutolike", 1)
	_check("Mars solar flux ~586 W/m2", mars.stellar_flux > 550.0 and mars.stellar_flux < 620.0)
	_check("Titan solar flux ~15 W/m2", titan.stellar_flux > 12.0 and titan.stellar_flux < 18.0)
	_check("Pluto solar flux ~0.87 W/m2", pluto.stellar_flux > 0.70 and pluto.stellar_flux < 1.10)

	var random_world := PlanetParameters.from_random(987654)
	var expected_g := SciConstants.G * random_world.mass / (random_world.radius * random_world.radius)
	_check("random planets finalize derived gravity", absf(random_world.surface_gravity - expected_g) / expected_g < 1e-10)
	_check("random planets finalize stellar flux", random_world.stellar_flux > 0.0 and random_world.stellar_flux != SciConstants.SOLAR_FLUX_EARTH)

	# Radiation.
	_check("sigma*255^4 ~= 240 W/m2", absf(SciConstants.SIGMA * pow(255.0, 4.0) - 240.0) < 2.0)
	_check("sigma*5772^4 ~= 6.3e7 W/m2", absf(SciConstants.SIGMA * pow(5772.0, 4.0) - 6.3e7) < 5e6)

	# Reference atmosphere and local hydrostatic column.
	var solver := CoupledPlanetSolver.new(earth, 1)
	var atm: AtmosphereState = solver.atmosphere
	_check("Earth preset pressure ~= 101325 Pa", absf(atm.total_pressure - SciConstants.EARTH_PRESSURE) < 1.0)
	_check("Earth preset is N2-dominant", atm.mole_fraction("N2") > 0.77 and atm.mole_fraction("N2") < 0.79)
	_check("Earth preset O2 ~20.9%", atm.mole_fraction("O2") > 0.20 and atm.mole_fraction("O2") < 0.22)
	_check("ideal gas rho = P M / RT", absf(atm.density - atm.total_pressure * atm.mean_molar_mass / (SciConstants.R_u * atm.temperature)) < 1e-6)
	_check("scale height equation", absf(atm.scale_height - SciConstants.R_u * atm.temperature / (atm.mean_molar_mass * atm.gravity)) < 1e-3)
	var high := AtmosphereModel.local_state(atm, 1000.0, atm.temperature)
	_check("pressure decreases with elevation", high.total_pressure < atm.total_pressure)
	_check("hydrostatic 1 km pressure ratio plausible", high.total_pressure / atm.total_pressure > 0.82 and high.total_pressure / atm.total_pressure < 0.94)

	# Phase reference points.
	_check("H2O triple T", absf(SpeciesDatabase.triple_temperature("H2O") - 273.16) < 0.01)
	_check("H2O triple P", absf(SpeciesDatabase.triple_pressure("H2O") - 611.657) < 1.0)
	_check("CO2 triple T", absf(SpeciesDatabase.triple_temperature("CO2") - 216.59) < 0.02)
	_check("CO2 triple P", absf(SpeciesDatabase.triple_pressure("CO2") - 5.1795e5) < 100.0)
	_check("CO2 below triple pressure cannot be liquid", PhaseSolver.phase_of("CO2", 220.0, 4.0e5)["phase"] != PhaseSolver.PHASE_LIQUID)
	_check("H2O 300 K 1 bar is liquid", PhaseSolver.phase_of("H2O", 300.0, 1.0e5)["phase"] == PhaseSolver.PHASE_LIQUID)
	_check("CO2 350 K 100 bar is supercritical", PhaseSolver.phase_of("CO2", 350.0, 1.0e7)["phase"] == PhaseSolver.PHASE_SUPERCRITICAL)

	# Normative chemistry conservation / bounds.
	var budget := {"Si":0.21,"O":0.45,"Mg":0.05,"Fe":0.08,"Al":0.06,"Ca":0.05,"K":0.02,"Na":0.02,"Ti":0.005,"S":0.003,"C":0.001}
	var norm := EquilibriumSolver.norm(budget, {"crust":"felsic","hydrated":false})
	var consumed := 0.0
	for m in norm["minerals"]:
		consumed += float(m["fraction"])
		_check("mineral fraction nonnegative", float(m["fraction"]) >= 0.0)
	var residue := 0.0
	for e in norm["residue"].keys():
		residue += float(norm["residue"][e])
		_check("residue nonnegative", float(norm["residue"][e]) >= -1e-10)
	_check("norm minerals + residue conserve <= input", consumed + residue <= 1.001)

	var rock_sum := 0.0
	for e in earth.rock_element_fractions().keys():
		rock_sum += float(earth.rock_element_fractions()[e])
	_check("rock element fractions normalize", absf(rock_sum - 1.0) < 1e-4)

	# Full four-layer cell and probe correspondence.
	var chunk := solver.generate_chunk(0, 0)
	var rec: Dictionary = chunk["records"][0]
	var sub: SubstrateState = rec["substrate"]
	var thermal: ThermalState = rec["thermal"]
	var local_atm: AtmosphereState = rec["atmosphere"]
	_check("cell carries coupling metadata", rec.has("coupling") and int(rec["coupling"].get("iterations",0)) > 0)
	_check("cell temperatures finite", is_finite(thermal.temperature) and is_finite(local_atm.temperature))
	_check("cell pressure positive", local_atm.total_pressure > 0.0)
	_check("substrate bulk density <= grain density", sub.bulk_density <= sub.density + 1e-9)
	_check("substrate permeability nonnegative", sub.permeability_m2 >= 0.0)
	_check("thermal diffusivity physical", sub.thermal_diffusivity > 0.0 and sub.thermal_diffusivity < 1e-3)
	_check("energy residual finite", is_finite(thermal.residual_w_m2))

	var sample := SampleReport.build(rec, earth, solver, rec["position"])
	_check("sample position == record", sample["position"] == rec["position"])
	_check("sample ground temperature == solved cell", absf(float(sample["temperature"]) - thermal.temperature) < 1e-9)
	_check("sample pressure == LOCAL cell atmosphere", absf(float(sample["pressure"]) - local_atm.total_pressure) < 1e-9)
	_check("sample has mass and mole composition", not sample["elements_mass_pct"].is_empty() and not sample["elements_mole_pct"].is_empty())
	_check("sample exposes convergence metadata", sample["model"].has("coupling"))

	# Quantitative material fingerprints.
	var fp := DiscoverySystem.fingerprint(sample)
	_check("fingerprint has element vector", not fp["element_vector"].is_empty())
	_check("fingerprint has mineral vector", not fp["mineral_vector"].is_empty())
	_check("fingerprint self-distance == 0", DiscoverySystem.fingerprint_distance(fp, fp) < 1e-12)
	var changed := sample.duplicate(true)
	var changed_mass: Dictionary = changed["elements_mass_pct"]
	changed_mass["Fe"] = float(changed_mass.get("Fe", 0.0)) + 20.0
	var fp_changed := DiscoverySystem.fingerprint(changed)
	_check("composition change produces fingerprint distance", DiscoverySystem.fingerprint_distance(fp, fp_changed) > 0.001)
	var ds := DiscoverySystem.new()
	var first := ds.process(sample)
	var second := ds.process(sample)
	_check("first sample creates material signature", first["material_new"] == true)
	_check("identical sample reuses material signature", second["material_new"] == false and second["material_signature"] == first["material_signature"])

	# World-coordinate indexing across negative chunk coordinates.
	var gs_index := GameState.new()
	gs_index.init_planet("marslike", 71)
	var neg_cell := gs_index.cell_at_world(Vector2(-4.0, -4.0), true)
	_check("negative world coordinates map to correct cell", not neg_cell.is_empty() and neg_cell["position"] == Vector2(-4.0, -4.0))

	# Versioned save round-trip: seed/position/discovery state only, never chunks.
	var save_path := "user://star_hollow_ci_test.json"
	var gs_save := GameState.new()
	gs_save.init_planet("earthlike", 123)
	var fake_player := Node2D.new()
	fake_player.global_position = Vector2(-321.5, 778.25)
	gs_save.player = fake_player
	gs_save.discovery.process(sample)
	_check("save writes deterministic exploration state", SaveSystem.save_game(gs_save, save_path))
	var gs_load := GameState.new()
	var fake_loaded_player := Node2D.new()
	gs_load.player = fake_loaded_player
	var load_result := SaveSystem.load_game(gs_load, save_path)
	_check("save reload succeeds for same generator version", load_result.get("ok", false))
	_check("save preserves planet seed", gs_load.planet.seed == 123)
	_check("save preserves player position", fake_loaded_player.global_position.distance_to(Vector2(-321.5, 778.25)) < 1e-6)
	_check("save preserves material discoveries", gs_load.discovery.material_records.size() == gs_save.discovery.material_records.size())
	_check("save does not serialize chunk cache", gs_load.chunk_map.is_empty())

	print("== run_tests: %d assertions, %d failures ==" % [asserts, failures])
	quit(1 if failures > 0 else 0)

func _check(label: String, cond: bool) -> void:
	asserts += 1
	if cond:
		print("  [ok]  %s" % label)
	else:
		failures += 1
		print("  [FAIL] %s" % label)
