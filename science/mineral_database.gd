# mineral_database.gd
# -----------------------------------------------------------------------------
# Mineral / compound database with stoichiometric formulas, physical properties
# and (where available) standard Gibbs energies of formation.
#
# Source policy (see docs/science/SCIENCE_SOURCES.md):
#   * formula            — conventional mineralogy (Deer, Howie & Zussman; Mindat)
#   * density            — literature standard density (APPROX where rounded)
#   * thermal conductivity / specific heat — literature/engineering APPROX
#   * dG_f298            — standard Gibbs energy of formation, kJ/mol at 298.15 K
#                          (NIST / Barin thermodynamics; null when not reliable)
#   * reflectance        — HEURISTIC simplified visual reflectance (0..1 RGB)
#                          used ONLY by the renderer; never by the science core.
#
# The kinetic "norm" allocation in equilibrium_solver.gd consumes these
# stoichiometries directly; do not change formulas without revalidating
# conservation tests.
# -----------------------------------------------------------------------------
class_name MineralDatabase
extends RefCounted

## formula uses element-symbol -> atoms. H2O of hydration is folded into the
## formula (structural water) for mass-balance purposes.
const _MINERALS := {
	# --- silicates -----------------------------------------------------------
	"forsterite":    { "name": "olivine (forsterite)", "family": "olivine", "formula": {"Mg":2,"Si":1,"O":4}, "density": 3.22e3, "k": 4.0, "cp": 800.0, "dG_f298": -2145.0, "reflectance": Color(0.60,0.62,0.50) },
	"fayalite":      { "name": "olivine (fayalite)",   "family": "olivine", "formula": {"Fe":2,"Si":1,"O":4}, "density": 4.39e3, "k": 3.0, "cp": 640.0, "dG_f298": -1391.0, "reflectance": Color(0.42,0.36,0.28) },
	"enstatite":     { "name": "orthopyroxene (enstatite)", "family": "pyroxene", "formula": {"Mg":1,"Si":1,"O":3}, "density": 3.20e3, "k": 4.0, "cp": 770.0, "dG_f298": -1546.0, "reflectance": Color(0.45,0.47,0.42) },
	"ferrosilite":   { "name": "orthopyroxene (ferrosilite)", "family": "pyroxene", "formula": {"Fe":1,"Si":1,"O":3}, "density": 3.95e3, "k": 3.5, "cp": 650.0, "dG_f298": -1136.0, "reflectance": Color(0.38,0.34,0.27) },
	"diopside":      { "name": "clinopyroxene (diopside)", "family": "pyroxene", "formula": {"Ca":1,"Mg":1,"Si":2,"O":6}, "density": 3.27e3, "k": 4.0, "cp": 750.0, "dG_f298": -3027.0, "reflectance": Color(0.50,0.52,0.45) },
	"wollastonite":  { "name": "wollastonite", "family": "pyroxenoid", "formula": {"Ca":1,"Si":1,"O":3}, "density": 2.91e3, "k": 2.5, "cp": 710.0, "dG_f298": -1549.0, "reflectance": Color(0.78,0.78,0.74) },
	"albite":        { "name": "feldspar (albite)", "family": "feldspar", "formula": {"Na":1,"Al":1,"Si":3,"O":8}, "density": 2.62e3, "k": 2.3, "cp": 750.0, "dG_f298": -3711.0, "reflectance": Color(0.86,0.85,0.82) },
	"anorthite":     { "name": "feldspar (anorthite)", "family": "feldspar", "formula": {"Ca":1,"Al":2,"Si":2,"O":8}, "density": 2.76e3, "k": 2.0, "cp": 720.0, "dG_f298": -4011.0, "reflectance": Color(0.80,0.80,0.77) },
	"orthoclase":    { "name": "feldspar (orthoclase)", "family": "feldspar", "formula": {"K":1,"Al":1,"Si":3,"O":8}, "density": 2.56e3, "k": 2.4, "cp": 700.0, "dG_f298": -3738.0, "reflectance": Color(0.85,0.62,0.58) },
	"quartz":        { "name": "silica (alpha-quartz)", "family": "silica", "formula": {"Si":1,"O":2}, "density": 2.65e3, "k": 7.7, "cp": 740.0, "dG_f298": -856.6, "reflectance": Color(0.88,0.88,0.86) },
	"glass":         { "name": "amorphous silicate glass", "family": "glass", "formula": {"Si":1,"O":2}, "density": 2.55e3, "k": 1.2, "cp": 750.0, "dG_f298": null, "reflectance": Color(0.30,0.28,0.26) },
	"corundum":      { "name": "corundum", "family": "oxide_aluminium", "formula": {"Al":2,"O":3}, "density": 3.98e3, "k": 30.0, "cp": 780.0, "dG_f298": -1582.0, "reflectance": Color(0.75,0.76,0.78) },
	"kaolinite":     { "name": "kaolinite clay", "family": "clay", "formula": {"Al":2,"Si":2,"O":9,"H":4}, "density": 2.60e3, "k": 1.4, "cp": 940.0, "dG_f298": -3800.0, "reflectance": Color(0.72,0.68,0.60) },
	# --- iron phases -----------------------------------------------------------
	"magnetite":     { "name": "magnetite", "family": "oxide_iron", "formula": {"Fe":3,"O":4}, "density": 5.18e3, "k": 5.1, "cp": 620.0, "dG_f298": -1013.0, "reflectance": Color(0.16,0.16,0.18) },
	"hematite":      { "name": "hematite", "family": "oxide_iron", "formula": {"Fe":2,"O":3}, "density": 5.27e3, "k": 5.0, "cp": 630.0, "dG_f298": -742.0, "reflectance": Color(0.42,0.16,0.12) },
	"iron_metal":    { "name": "metallic iron", "family": "metal", "formula": {"Fe":1}, "density": 7.87e3, "k": 80.0, "cp": 450.0, "dG_f298": 0.0, "reflectance": Color(0.72,0.72,0.74) },
	"nickel_metal":  { "name": "metallic nickel", "family": "metal", "formula": {"Ni":1}, "density": 8.91e3, "k": 90.0, "cp": 440.0, "dG_f298": 0.0, "reflectance": Color(0.74,0.74,0.72) },
	"troilite":      { "name": "troilite (iron sulfide)", "family": "sulfide_iron", "formula": {"Fe":1,"S":1}, "density": 4.67e3, "k": 4.0, "cp": 420.0, "dG_f298": -97.5, "reflectance": Color(0.40,0.37,0.30) },
	"pyrite":        { "name": "pyrite", "family": "sulfide_iron", "formula": {"Fe":1,"S":2}, "density": 5.02e3, "k": 30.0, "cp": 520.0, "dG_f298": -160.0, "reflectance": Color(0.80,0.78,0.55) },
	"siderite":      { "name": "siderite", "family": "carbonate", "formula": {"Fe":1,"C":1,"O":3}, "density": 3.96e3, "k": 2.0, "cp": 730.0, "dG_f298": -671.0, "reflectance": Color(0.60,0.52,0.38) },
	"ilmenite":      { "name": "ilmenite", "family": "oxide_titanium", "formula": {"Fe":1,"Ti":1,"O":3}, "density": 4.72e3, "k": 3.5, "cp": 620.0, "dG_f298": -1158.0, "reflectance": Color(0.30,0.28,0.27) },
	"rutile":        { "name": "rutile", "family": "oxide_titanium", "formula": {"Ti":1,"O":2}, "density": 4.25e3, "k": 9.0, "cp": 690.0, "dG_f298": -890.0, "reflectance": Color(0.55,0.48,0.45) },
	# --- carbon ---------------------------------------------------------------
	"graphite":      { "name": "graphite", "family": "carbon", "formula": {"C":1}, "density": 2.25e3, "k": 130.0, "cp": 710.0, "dG_f298": 0.0, "reflectance": Color(0.20,0.20,0.20) },
	"diamond":       { "name": "diamond", "family": "carbon", "formula": {"C":1}, "density": 3.52e3, "k": 1000.0, "cp": 520.0, "dG_f298": 2.9, "reflectance": Color(0.95,0.96,0.97) },
	"sulfur":        { "name": "native sulfur", "family": "native_sulfur", "formula": {"S":1}, "density": 2.07e3, "k": 0.20, "cp": 710.0, "dG_f298": 0.0, "reflectance": Color(0.90,0.78,0.20) },
	# --- salts / evaporites -----------------------------------------------------
	"halite":        { "name": "halite", "family": "salt_halide", "formula": {"Na":1,"Cl":1}, "density": 2.17e3, "k": 6.5, "cp": 860.0, "dG_f298": -384.0, "reflectance": Color(0.93,0.93,0.95) },
	"sylvite":       { "name": "sylvite", "family": "salt_halide", "formula": {"K":1,"Cl":1}, "density": 1.99e3, "k": 6.0, "cp": 690.0, "dG_f298": -409.0, "reflectance": Color(0.95,0.90,0.92) },
	"anhydrite":     { "name": "anhydrite", "family": "sulfate", "formula": {"Ca":1,"S":1,"O":4}, "density": 2.98e3, "k": 4.8, "cp": 690.0, "dG_f298": -1321.0, "reflectance": Color(0.88,0.88,0.90) },
	"gypsum":        { "name": "gypsum", "family": "sulfate", "formula": {"Ca":1,"S":1,"O":8,"H":4}, "density": 2.32e3, "k": 2.0, "cp": 1090.0, "dG_f298": -1797.0, "reflectance": Color(0.90,0.89,0.85) },
	"calcite":       { "name": "calcite", "family": "carbonate", "formula": {"Ca":1,"C":1,"O":3}, "density": 2.71e3, "k": 3.3, "cp": 820.0, "dG_f298": -1129.0, "reflectance": Color(0.88,0.87,0.83) },
	"dolomite":      { "name": "dolomite", "family": "carbonate", "formula": {"Ca":1,"Mg":1,"C":2,"O":6}, "density": 2.84e3, "k": 3.1, "cp": 810.0, "dG_f298": -2161.0, "reflectance": Color(0.86,0.85,0.82) },
	# --- volatile ices (pure condensed phases) ----------------------------------
	"water_ice":     { "name": "water ice (Ih)", "family": "ice_h2o", "formula": {"H":2,"O":1}, "density": 9.17e2, "k": 2.2, "cp": 2090.0, "dG_f298": -236.6, "reflectance": Color(0.84,0.91,0.99) },
	"co2_ice":       { "name": "carbon dioxide ice", "family": "ice_co2", "formula": {"C":1,"O":2}, "density": 1.56e3, "k": 0.6, "cp": 1090.0, "dG_f298": -386.0, "reflectance": Color(0.93,0.94,0.96) },
	"n2_ice":        { "name": "nitrogen ice", "family": "ice_n2", "formula": {"N":2}, "density": 1.03e3, "k": 0.8, "cp": 1500.0, "dG_f298": null, "reflectance": Color(0.88,0.90,0.93) },
	"ch4_ice":       { "name": "methane ice", "family": "ice_ch4", "formula": {"C":1,"H":4}, "density": 4.94e2, "k": 0.6, "cp": 1900.0, "dG_f298": null, "reflectance": Color(0.80,0.88,0.90) },
	"nh3_ice":       { "name": "ammonia ice", "family": "ice_nh3", "formula": {"N":1,"H":3}, "density": 8.17e2, "k": 2.0, "cp": 2200.0, "dG_f298": null, "reflectance": Color(0.92,0.90,0.88) },
	"co_ice":        { "name": "carbon monoxide ice", "family": "ice_co", "formula": {"C":1,"O":1}, "density": 9.23e2, "k": 0.6, "cp": 1600.0, "dG_f298": null, "reflectance": Color(0.90,0.91,0.93) },
	"so2_ice":       { "name": "sulfur dioxide ice", "family": "ice_so2", "formula": {"S":1,"O":2}, "density": 1.83e3, "k": 0.6, "cp": 1200.0, "dG_f298": null, "reflectance": Color(0.88,0.87,0.80) },
	# --- organic --------------------------------------------------------------
	"tholin":        { "name": "complex refractory organics (tholin-like)", "family": "organic", "formula": {"C":1,"H":0.9,"N":0.1}, "density": 1.30e3, "k": 0.2, "cp": 1200.0, "dG_f298": null, "reflectance": Color(0.42,0.26,0.16) },
}

const ROCK_MINERALS := [
	"forsterite", "fayalite", "enstatite", "ferrosilite", "diopside", "wollastonite",
	"albite", "anorthite", "orthoclase", "quartz", "glass", "corundum", "kaolinite",
	"magnetite", "hematite", "iron_metal", "nickel_metal", "troilite", "pyrite",
	"siderite", "ilmenite", "rutile", "graphite", "sulfur", "halite", "sylvite",
	"anhydrite", "gypsum", "calcite", "dolomite",
]

const ICE_MINERALS := [
	"water_ice", "co2_ice", "n2_ice", "ch4_ice", "nh3_ice", "co_ice", "so2_ice",
]

static func has(mineral_id: String) -> bool:
	return _MINERALS.has(mineral_id)

static func get_mineral(mineral_id: String) -> Dictionary:
	return _MINERALS[mineral_id]

static func formula(mineral_id: String) -> Dictionary:
	return _MINERALS[mineral_id]["formula"]

static func family(mineral_id: String) -> String:
	return _MINERALS[mineral_id]["family"]

static func display_name(mineral_id: String) -> String:
	return _MINERALS[mineral_id]["name"]

static func molar_mass_kg(mineral_id: String) -> float:
	var f: Dictionary = formula(mineral_id)
	var m := 0.0
	for sym in f.keys():
		m += ElementDatabase.mass_kg_per_mol(sym) * f[sym]
	return m

static func density(mineral_id: String) -> float:
	return _MINERALS[mineral_id]["density"]

static func thermal_conductivity(mineral_id: String) -> float:
	return _MINERALS[mineral_id]["k"]

static func specific_heat(mineral_id: String) -> float:
	return _MINERALS[mineral_id]["cp"]

static func gibbs_formation(mineral_id: String) -> float:
	# kJ/mol, 298.15 K; null entries fall back to 0 in ranking and are flagged.
	return _MINERALS[mineral_id]["dG_f298"]

static func has_gibbs(mineral_id: String) -> bool:
	return _MINERALS[mineral_id]["dG_f298"] != null

static func reflectance(mineral_id: String) -> Color:
	return _MINERALS[mineral_id]["reflectance"]

## All mineral ids.
static func all_ids() -> Array:
	return _MINERALS.keys()

static func provenance_report() -> String:
	var l: Array[String] = []
	l.append("## MineralDatabase provenance")
	l.append("Formulas: conventional mineralogy (Deer, Howie & Zussman / Mindat).")
	l.append("Density, k, cp: literature standard values, APPROX where rounded.")
	l.append("dG_f298: standard Gibbs energy of formation (298.15 K), NIST/Barin-type")
	l.append("  tabulations; entries marked null are not used in stability ranking.")
	l.append("reflectance: HEURISTIC simplified visual reflectance, renderer-only.")
	return "\n".join(l)