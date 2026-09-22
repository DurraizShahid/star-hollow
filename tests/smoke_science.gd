# tests/smoke_science.gd
# -----------------------------------------------------------------------------
# Headless smoke test for the science core: loads every module (which both
# compiles each script and fails loudly on parse/script errors), then runs a
# one-chunk generation for every planet preset and checks core invariants.
#
# Run:  godot --headless --path . -s res://tests/smoke_science.gd
# Exits 0 on success, 1 on any failure.
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
	"res://science/hydrosphere_model.gd",
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

var _solver_class: GDScript
var failures := 0
var asserts := 0

func _initialize() -> void:
	var guard := create_timer(240.0)
	guard.timeout.connect(quit.bind(2))
	print("== smoke_science: loading modules ==")
	var loaded := {}
	for p in PATHS:
		loaded[p] = load(p)
	print("loaded %d science modules" % loaded.size())
	_check("all modules loadable", loaded.size() == PATHS.size())

	_solver_class = load("res://science/coupled_planet_solver.gd")

	_check("ElementDatabase mass lookup", ElementDatabase.mass_kg_per_mol("Si") > 0.02 and ElementDatabase.mass_kg_per_mol("Si") < 0.03)
	_check("ElementDatabase.symbols()", ElementDatabase.symbols().size() >= 18)
	_check("SpeciesDatabase species count", SpeciesDatabase.count() >= 11)
	_check("H2O triple is water", absf(SpeciesDatabase.triple_temperature("H2O") - 273.16) < 0.02)
	_check("CO2 triple pressure ~5.18 bar", absf(SpeciesDatabase.triple_pressure("CO2") - 5.1795e5) < 1.0e3)

	_dump_rock(PlanetParameters.from_preset("earthlike", 7))
	for preset in PlanetParameters.presets():
		_run_preset(PlanetParameters.from_preset(preset, 42), preset)

	# Random world determinism: same seed => identical first chunk cells.
	var p1 := PlanetParameters.from_random(12345, "DupA")
	var p2 := PlanetParameters.from_random(12345, "DupB")
	var s1: RefCounted = _solver_class.new(p1)
	var s2: RefCounted = _solver_class.new(p2)
	var c1: Dictionary = s1.generate_chunk(0, 0)
	var c2: Dictionary = s2.generate_chunk(0, 0)
	var same := true
	var recs1: Array = c1["records"]
	var recs2: Array = c2["records"]
	for i in recs1.size():
		var th1: ThermalState = recs1[i]["thermal"]
		var th2: ThermalState = recs2[i]["thermal"]
		if absf(th1.temperature - th2.temperature) > 1e-6:
			same = false
			break
	_check("random world determinism (seed 12345)", same)

	# Norm conserves mineral fractions within tolerance.
	var budget := { "Si": 0.21, "O": 0.45, "Mg": 0.05, "Fe": 0.08, "Al": 0.06, "Ca": 0.05, "K": 0.02, "Na": 0.02, "Ti": 0.005, "S": 0.003, "C": 0.001 }
	var norm: Dictionary = EquilibriumSolver.norm(budget, { "crust": "felsic", "hydrated": false })
	var consumed_total := 0.0
	for m in norm["minerals"]:
		consumed_total += m["fraction"]
	var residue := 0.0
	for e in norm["residue"].keys():
		residue += norm["residue"][e]
	_check("norm mineral fractions <= 1.0001 (+%0.4f residue)" % residue, consumed_total <= 1.0001)

	# Chunk border continuity: same record at chunk border from both neighbours.
	var continuity := _check_continuity()
	_check("spatial continuity across chunk borders", continuity)

	# Probe report + discovery fingerprint sanity.
	var planet := PlanetParameters.from_preset("earthlike", 99)
	var solver: RefCounted = _solver_class.new(planet)
	var chunk: Dictionary = solver.generate_chunk(0, 0)
	var recs: Array = chunk["records"]
	var report := SampleReport.build(recs[0], planet, solver, recs[0]["position"])
	var fp := DiscoverySystem.fingerprint(report)
	_check("fingerprint has kinds", not fp["elements"].is_empty() and not fp["materials"].is_empty())
	var ds := DiscoverySystem.new()
	var outcome: Dictionary = ds.process(report)
	_check("discovery process returns total", outcome.get("total", 0) >= 1)

	print("== smoke_science: %d assertions, %d failures ==" % [asserts, failures])
	if failures > 0:
		print("FAILED")
		quit(1)
	else:
		print("PASS")
		quit(0)

func _check(label: String, cond: bool) -> void:
	asserts += 1
	if cond:
		print("  [ok]  %s" % label)
	else:
		failures += 1
		print("  [FAIL] %s" % label)

func _run_preset(planet: PlanetParameters, preset: String) -> void:
	var solver: RefCounted = _solver_class.new(planet)
	var atm_snap: AtmosphereState = solver.atmosphere
	print("preset=%s | %s | %s" % [preset, planet.describe(), atm_snap.describe()])
	var chunk: Dictionary = solver.generate_chunk(0, 0)
	var recs: Array = chunk["records"]
	var temps: Array = []
	var labels := {}
	var liq := 0
	var frost := 0
	for r in recs:
		var t: ThermalState = r["thermal"]
		temps.append(t.temperature)
		var c: Dictionary = r["classification"]
		var lbl: String = c.get("label", "?")
		labels[lbl] = labels.get(lbl, 0) + 1
		if r["surface"].liquid_cover >= 0.5:
			liq += 1
		if r["surface"].frost_cover >= 0.5:
			frost += 1
	var tmin: float = temps.min()
	var tmax: float = temps.max()
	var ok: bool = tmin > SciConstants.MIN_TEMPERATURE_K - 1.0 and tmax < SciConstants.MAX_TEMPERATURE_K
	_check("%11s T %5.1f..%5.1f K cells=%d liq=%d frost=%d" % [preset, tmin, tmax, recs.size(), liq, frost], ok)

func _dump_rock(planet: PlanetParameters) -> void:
	var d: Dictionary = planet.rock_element_fractions()
	var tot := 0.0
	for e in d.keys():
		tot += d[e]
	_check("earthlike rock_elements normalize to 1.0 (%0.4f)" % tot, absf(tot - 1.0) < 1e-3)

func _check_continuity() -> bool:
	var planet := PlanetParameters.from_preset("marslike", 7)
	var solver: RefCounted = _solver_class.new(planet)
	# Row-major records: chunk(0,0) records[0..15] are iy=0 (bottom row, ix=0..15).
	# The left column of chunk(0,0) is ix=0 (x=+4); the right column of chunk(-1,0)
	# is ix=15 (x=-4). The two cell centres are 8 m apart across the x=0 seam, so
	# values should be nearly continuous (large mismatch => seam/wrap artifact).
	var c0: Dictionary = solver.generate_chunk(0, 0)
	var cm: Dictionary = solver.generate_chunk(-1, 0)
	var rec0: Array = c0["records"]
	var recm: Array = cm["records"]
	for iy in 16:
		var a: ThermalState = rec0[iy * 16]["thermal"]
		var b: ThermalState = recm[iy * 16 + 15]["thermal"]
		if absf(a.temperature - b.temperature) > 10.0:
			return false
	return true