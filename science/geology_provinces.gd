# geology_provinces.gd
# -----------------------------------------------------------------------------
# Geological province / crustal-archetype definitions (DATA ONLY).
#
# Provinces establish *boundary conditions* (what kinds of crust are present,
# where basins/volcanism/cratons occur). They do NOT select materials directly;
# the coupled solver derives materials from these boundary conditions plus
# physics/chemistry. Element budgets below are literature-scaled crustal
# archetype approximations (fidelity: empirical). See docs/science/PROCEDURAL_GEOLOGY.md.
# -----------------------------------------------------------------------------
class_name GeologyProvinces
extends RefCounted

## Crust archetypes: dominant mass fractions of the non-volatile rock budget.
const CRUSTS := {
	"felsic": {
		"name": "felsic crust",
		"elements": {"O":47.0, "Si":29.0, "Al":8.0, "K":3.1, "Na":2.7, "Ca":2.5, "Fe":2.5, "Mg":1.2, "Ti":0.4, "P":0.06, "Mn":0.05, "Cr":0.01, "C":0.3, "S":0.03, "N":0.005},
	},
	"mafic": {
		"name": "mafic basaltic crust",
		"elements": {"O":44.0, "Si":23.0, "Fe":8.5, "Mg":4.5, "Ca":6.8, "Al":7.6, "Na":0.5, "K":0.2, "Ti":0.9, "P":0.1, "Mn":0.2, "Cr":0.03, "C":0.2, "S":0.1, "N":0.002},
	},
	"ultramafic": {
		"name": "ultramafic crust",
		"elements": {"O":45.0, "Si":20.0, "Mg":12.0, "Fe":10.0, "Ca":2.5, "Al":2.0, "Na":0.1, "K":0.05, "Ti":0.2, "P":0.05, "Mn":0.15, "Cr":0.3, "C":0.3, "S":0.3, "N":0.002},
	},
	"metallic": {
		"name": "metallic crustal exposure",
		"elements": {"Fe":55.0, "Ni":4.0, "S":5.0, "O":18.0, "Si":10.0, "Mg":3.0, "Al":1.5, "Ca":1.0, "Na":0.3, "K":0.15, "Ti":0.2, "P":0.15, "Cr":1.0, "Mn":0.3, "C":1.0},
	},
	"carbonaceous": {
		"name": "carbonaceous crust",
		"elements": {"C":30.0, "O":38.0, "Si":14.0, "Fe":9.0, "Mg":3.5, "Al":1.5, "Ca":1.2, "Na":0.4, "K":0.2, "S":1.0, "Ni":0.3, "Ti":0.1, "P":0.1, "N":0.5, "Cr":0.1, "Mn":0.05, "Cl":0.05},
	},
	"sediment": {
		"name": "mature sediment basin",
		"elements": {"O":49.0, "Si":31.0, "Al":7.0, "Fe":3.0, "Ca":2.0, "Na":1.0, "K":1.5, "Mg":1.0, "Ti":0.4, "P":0.05, "Mn":0.05, "C":2.0, "S":0.3, "N":0.01, "Cl":0.02},
	},
	"evaporite": {
		"name": "evaporite basin",
		"elements": {"O":45.0, "Si":10.0, "Ca":12.0, "Na":9.0, "Cl":9.0, "S":8.0, "C":2.0, "Mg":2.0, "K":0.5, "Fe":1.5, "Al":0.5, "Ti":0.05, "P":0.05},
	},
	"hydrothermal": {
		"name": "hydrothermal province",
		"elements": {"O":43.0, "Si":22.0, "Fe":10.0, "S":6.0, "Mg":3.0, "Ca":4.0, "Al":5.0, "Na":1.0, "K":0.6, "Ti":0.3, "C":0.8, "H":1.0, "P":0.1, "Mn":0.2, "Cl":0.5},
	},
}

## Province definitions.
## crust   : which crust-archetype supplies the bulk budget
## classes : igneous | sedimentary | metamorphic | volatile  (used by naming rules)
## flags   : basin, hydrothermal, volcanic, polar, crater
## color   : DEBUG OVERLAY color only (never used for terrain appearance)
const PROVINCES := {
	"craton_highlands":  { "name": "cratonic highlands",  "crust": "felsic",        "classes": ["igneous", "metamorphic"], "flags": [],             "color": Color(0.66,0.62,0.72) },
	"volcanic":          { "name": "volcanic province",   "crust": "mafic",         "classes": ["igneous", "volcanic"],   "flags": ["volcanic"],   "color": Color(0.75,0.28,0.18) },
	"ultramafic_massif": { "name": "ultramafic massif",   "crust": "ultramafic",    "classes": ["igneous"],               "flags": [],             "color": Color(0.45,0.55,0.35) },
	"impact_crater":     { "name": "impact basin",        "crust": "craton_highlands", "classes": ["metamorphic"],        "flags": ["crater", "basin"], "color": Color(0.8,0.6,0.5) },
	"sediment_basin":    { "name": "sediment basin",      "crust": "sediment",      "classes": ["sedimentary"],          "flags": ["basin"],       "color": Color(0.85,0.75,0.55) },
	"evaporite_flat":    { "name": "evaporite flat",      "crust": "evaporite",     "classes": ["sedimentary", "evaporite"], "flags": ["basin"],  "color": Color(0.92,0.92,0.80) },
	"hydrothermal":      { "name": "hydrothermal field",  "crust": "hydrothermal",  "classes": ["hydrothermal"],         "flags": ["hydrothermal"], "color": Color(0.35,0.75,0.45) },
	"metallic_exposure": { "name": "metallic exposure",   "crust": "metallic",      "classes": ["metal"],                "flags": ["metallic"],    "color": Color(0.7,0.7,0.75) },
	"carbon_terrain":    { "name": "carbon-rich terrain", "crust": "carbonaceous",  "classes": ["carbonaceous"],         "flags": [],              "color": Color(0.25,0.25,0.28) },
}

static func crust_ids() -> Array:
	return CRUSTS.keys()

static func province_ids() -> Array:
	return PROVINCES.keys()

static func get_crust(id: String) -> Dictionary:
	return CRUSTS[id]

static func get_province(id: String) -> Dictionary:
	return PROVINCES[id]

static func crust_of_province(province_id: String) -> String:
	if not PROVINCES.has(province_id):
		return "felsic"
	return resolve_crust(PROVINCES[province_id]["crust"])

## Crust enrichment factors: multiplier applied to the planet-average rock
## element budget within a crustal zone before normative allocation.
const CRUST_ENRICHMENT := {
	"felsic":       { "Si": 1.18, "Al": 1.20, "K": 1.40, "Na": 1.12, "Ca": 0.82, "Mg": 0.60, "Fe": 0.58, "Ti": 0.62 },
	"mafic":        { "Si": 0.95, "Al": 0.92, "Ca": 1.18, "Mg": 1.55, "Fe": 1.45, "Ti": 1.30, "Na": 0.80, "K": 0.50 },
	"ultramafic":   { "Si": 0.80, "Mg": 2.10, "Fe": 1.95, "Ca": 0.62, "Al": 0.62, "Na": 0.40, "K": 0.25, "Ti": 0.95 },
	"metallic":     { "Fe": 3.40, "Ni": 2.40, "S": 1.90, "Si": 0.32, "Mg": 0.42, "Al": 0.34, "Ca": 0.35 },
	"carbonaceous": { "C": 4.20, "Si": 0.86, "S": 1.30, "Fe": 1.10, "Mg": 1.20, "Ca": 0.92, "Al": 0.80, "N": 2.00 },
	"sediment":     { "Si": 1.05, "Ca": 1.30, "C": 1.25, "Al": 1.00, "Mg": 1.00, "Fe": 0.92, "Na": 1.20, "Cl": 1.60 },
	"evaporite":    { "Na": 1.90, "Cl": 2.20, "S": 1.80, "Ca": 1.30, "C": 1.20, "Mg": 1.30, "K": 1.55 },
	"hydrothermal": { "S": 2.20, "Fe": 1.40, "Ca": 1.20, "Al": 1.00, "Cl": 1.40 },
}

static func crust_enrichment(crust_id: String) -> Dictionary:
	return CRUST_ENRICHMENT.get(crust_id, {})

## Resolve a province's crust id when it references another province.
static func resolve_crust(crust_or_province: String) -> String:
	if CRUSTS.has(crust_or_province):
		return crust_or_province
	if PROVINCES.has(crust_or_province):
		var c: String = PROVINCES[crust_or_province]["crust"]
		return resolve_crust(c)
	return "mafic"