# tests/run_tests.gd
# -----------------------------------------------------------------------------
# Focused physics assertions for the science core.
#
# Run:  godot --headless --path . -s res://tests/run_tests.gd
# Exits 0 on success, 1 on failure.
# -----------------------------------------------------------------------------
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
	"res://science/equilibrium_solver.gd",
	"res://science/coupled_planet_solver.gd",
	"res://science/sample_report.gd",
	"res://science/discovery_system.gd",
]

const CELL_SIZE := 8.0

var _solver_class: GDScript
var failures := 0
var asserts := 0

func _initialize() -> void:
	var guard := create_timer(120.0)
	guard.timeout.connect(quit.bind(2))

	for p in PATHS:
		load(p)
	_solver_class = load("res://science/coupled_planet_solver.gd")

	# ---- gravity: g = G M / R^2 ----
	var p_earth := PlanetParameters.from_preset("earthlike", 1)
	_check("earthlike gravity ~= 9.81 m/s2", absf(p_earth.surface_gravity - SciConstants.EARTH_GRAVITY) < 0.05)

	# ---- equilibrium temperature ----
	_check("earthlike T_eq ~= 255 K", absf(p_earth.equilibrium_temperature - 255.0) < 2.0)
	var p_mars := PlanetParameters.from_preset("marslike", 1)
	_check("marslike T_eq < earthlike T_eq", p_mars.equilibrium_temperature < p_earth.equilibrium_temperature)

	# ---- Stefan-Boltzmann ----
	_check("sigma * 255^4 ~= 240 W/m2", absf(SciConstants.SIGMA * pow(255.0, 4.0) - 240.0) < 2.0)
	_check("sigma * 5772^4 ~= 6.3e7 W/m2", absf(SciConstants.SIGMA * pow(5772.0, 4.0) - 6.3e7) < 5e6)

	# ---- atmosphere: ideal gas + scale height ----
	var solver: RefCounted = _solver_class.new(p_earth)
	var atm: AtmosphereState = solver.atmosphere
	var chunk: Dictionary = solver.generate_chunk(0, 0)
	var recs: Array = chunk["records"]
	var rec: Dictionary = recs[0]
	var sub: SubstrateState = rec["substrate"]
	_check("ideal gas rho = P M / (R T)", absf(atm.density - atm.total_pressure * atm.mean_molar_mass / (SciConstants.R_u * atm.temperature)) < 1e-6)
	_check("scale height H = R T / (M g)", absf(atm.scale_height - SciConstants.R_u * atm.temperature / (atm.mean_molar_mass * atm.gravity)) < 1e-3)
	_check("thermal diffusivity in rock range", sub.thermal_diffusivity > 5e-7 and sub.thermal_diffusivity < 5e-5)
	_check("explicit diffusion dt stable >> 100 s", (CELL_SIZE * CELL_SIZE) / (2.0 * sub.thermal_diffusivity) > 100.0)

	# ---- phase reference points ----
	_check("H2O triple T = 273.16 K", absf(SpeciesDatabase.triple_temperature("H2O") - 273.16) < 0.01)
	_check("H2O triple P ~= 611.657 Pa", absf(SpeciesDatabase.triple_pressure("H2O") - 611.657) < 1.0)
	_check("CO2 triple T = 216.59 K", absf(SpeciesDatabase.triple_temperature("CO2") - 216.59) < 0.01)
	_check("CO2 triple P ~= 5.1795e5 Pa", absf(SpeciesDatabase.triple_pressure("CO2") - 5.1795e5) < 10.0)
	_check("CO2 below triple pressure is not liquid", PhaseSolver.phase_of("CO2", 220.0, 4.0e5)["phase"] != "liquid")
	_check("H2O at 300K 1e5 Pa is liquid", PhaseSolver.phase_of("H2O", 300.0, 1.0e5)["phase"] == "liquid")
	_check("CO2 above critical is supercritical", PhaseSolver.phase_of("CO2", 350.0, 1.0e7)["phase"] == "supercritical")

	# ---- conservation ----
	var budget := { "Si": 0.21, "O": 0.45, "Mg": 0.05, "Fe": 0.08, "Al": 0.06, "Ca": 0.05, "K": 0.02, "Na": 0.02, "Ti": 0.005, "S": 0.003, "C": 0.001 }
	var norm: Dictionary = EquilibriumSolver.norm(budget, {"crust": "felsic", "hydrated": false})
	var mass_sum := 0.0
	for m in norm["minerals"]:
		mass_sum += m["fraction"]
	for e in norm["residue"].keys():
		mass_sum += norm["residue"][e]
	_check("norm minerals+residue <= 1.001 (mass conserved)", mass_sum <= 1.001)
	var rock_sum := 0.0
	var rock_fracs := p_earth.rock_element_fractions()
	for e in rock_fracs.keys():
		rock_sum += rock_fracs[e]
	_check("rock_elements normalize to 1.0", absf(rock_sum - 1.0) < 1e-4)

	# ---- probe == sample correspondence ----
	var sample: Dictionary = SampleReport.build(rec, p_earth, solver, rec["position"])
	_check("sample position == record position", sample["position"] == rec["position"])
	_check("sample temperature == thermal temperature", absf(sample["temperature"] - rec["thermal"].temperature) < 1e-9)
	_check("sample pressure == atmosphere pressure", absf(sample["pressure"] - atm.total_pressure) < 1e-9)
	_check("sample gravity == planet gravity", absf(sample["gravity"] - p_earth.surface_gravity) < 1e-9)

	# ---- fingerprint ----
	var fp: Dictionary = DiscoverySystem.fingerprint(sample)
	_check("fingerprint has elements and materials", not fp["elements"].is_empty() and not fp["materials"].is_empty())
	_check("fingerprint has compounds", not fp["compounds"].is_empty())

	print("== run_tests: %d assertions, %d failures ==" % [asserts, failures])
	if failures > 0:
		quit(1)
	quit(0)

func _check(label: String, cond: bool) -> void:
	asserts += 1
	if cond:
		print("  [ok]  %s" % label)
	else:
		failures += 1
		print("  [FAIL] %s" % label)
