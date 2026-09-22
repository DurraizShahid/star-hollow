# element_database.gd
# -----------------------------------------------------------------------------
# Periodic-table data for the elements tracked in the simulation.
#
# All unit-less atomic weights are `standard atomic weights` (IUPAC, as printed
# in the 2019 concise tables). Masses in g/mol; convert to kg/mol as needed.
#
# This module is data only — no simulation logic. It is shared by the
# geochemistry, probe and discovery subsystems.
# -----------------------------------------------------------------------------
class_name ElementDatabase
extends RefCounted

const _ELEMENTS := {
	# symbol -> { name, z, mass (g/mol), class }
	"H":  { "name": "hydrogen",           "z": 1,  "mass": 1.008,   "class": "volatile" },
	"He": { "name": "helium",             "z": 2,  "mass": 4.0026,  "class": "noble" },
	"C":  { "name": "carbon",             "z": 6,  "mass": 12.011,  "class": "rock" },
	"N":  { "name": "nitrogen",           "z": 7,  "mass": 14.007,  "class": "volatile" },
	"O":  { "name": "oxygen",             "z": 8,  "mass": 15.999,  "class": "rock" },
	"Na": { "name": "sodium",             "z": 11, "mass": 22.990,  "class": "rock" },
	"Mg": { "name": "magnesium",          "z": 12, "mass": 24.305,  "class": "rock" },
	"Al": { "name": "aluminium",          "z": 13, "mass": 26.982,  "class": "rock" },
	"Si": { "name": "silicon",            "z": 14, "mass": 28.085,  "class": "rock" },
	"P":  { "name": "phosphorus",         "z": 15, "mass": 30.974,  "class": "rock" },
	"S":  { "name": "sulfur",             "z": 16, "mass": 32.06,   "class": "rock" },
	"Cl": { "name": "chlorine",           "z": 17, "mass": 35.45,   "class": "volatile" },
	"K":  { "name": "potassium",          "z": 19, "mass": 39.098,  "class": "rock" },
	"Ca": { "name": "calcium",            "z": 20, "mass": 40.078,  "class": "rock" },
	"Ti": { "name": "titanium",           "z": 22, "mass": 47.867,  "class": "rock" },
	"Cr": { "name": "chromium",           "z": 24, "mass": 51.996,  "class": "rock" },
	"Mn": { "name": "manganese",          "z": 25, "mass": 54.938,  "class": "rock" },
	"Fe": { "name": "iron",               "z": 26, "mass": 55.845,  "class": "rock" },
	"Ni": { "name": "nickel",             "z": 28, "mass": 58.693,  "class": "rock" },
}

static func symbols() -> Array:
	return _ELEMENTS.keys()

static func count() -> int:
	return _ELEMENTS.size()

static func has_symbol(sym: String) -> bool:
	return _ELEMENTS.has(sym)

static func mass_grams_per_mol(sym: String) -> float:
	return _ELEMENTS[sym]["mass"]

static func mass_kg_per_mol(sym: String) -> float:
	return _ELEMENTS[sym]["mass"] * 1e-3

static func name(sym: String) -> String:
	return _ELEMENTS[sym]["name"]

static func atomic_number(sym: String) -> int:
	return _ELEMENTS[sym]["z"]

static func element_class(sym: String) -> String:
	return _ELEMENTS[sym]["class"]

## Mole fraction -> mass fraction (given element symbols and mole fractions summing to 1).
static func mole_to_mass_fractions(symbols_arr: Array, mole_fracs: Array) -> Dictionary:
	var out := {}
	var total := 0.0
	for i in symbols_arr.size():
		var sym: String = symbols_arr[i]
		var m: float = mass_grams_per_mol(sym) * float(mole_fracs[i])
		total += m
		out[sym] = m
	if total <= 0.0:
		return out
	for k in out.keys():
		out[k] = out[k] / total
	return out

## Mass fraction -> mole fraction.
static func mass_to_mole_fractions(mass_fracs: Dictionary) -> Dictionary:
	var out := {}
	var total := 0.0
	for sym in mass_fracs.keys():
		var m: float = float(mass_fracs[sym]) / mass_grams_per_mol(sym)
		total += m
		out[sym] = m
	if total <= 0.0:
		return out
	for k in out.keys():
		out[k] = out[k] / total
	return out