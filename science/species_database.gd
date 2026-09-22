# species_database.gd
# -----------------------------------------------------------------------------
# Data for atmospheric/labile chemical species (volatiles).
#
# Phase-reference data (triple point, critical point, normal boiling point,
# molar latent heats) come from standard references — primarily the CRC
# Handbook of Chemistry and Physics and NIST WebBook standard values. Where a
# value is an estimate rather than a measured standard it is flagged APPROX in
# the "provenance" field. See docs/science/SCIENCE_SOURCES.md.
#
# Vapor-pressure curves are NOT Antoine-coefficient tables; they are computed
# by thermodynamics.gd via a Watson-correlation integration anchored on
# (triple point, critical point). See docs/science/THERMODYNAMICS.md.
# -----------------------------------------------------------------------------
class_name SpeciesDatabase
extends RefCounted

## Keys: species symbol; values:
##   name              display name
##   Mm                molar mass (kg mol^-1)
##   t_triple          triple-point temperature (K)   | null if not applicable
##   p_triple          triple-point pressure (Pa)      | null if not applicable
##   t_crit            critical temperature (K)        | null if no critical point known
##   p_crit            critical pressure (Pa)          | null if not applicable
##   t_boil            normal boiling point at 101325 Pa (K) (optional, info only)
##   h_fus             molar enthalpy of fusion at triple point (J mol^-1)
##   h_vap             molar enthalpy of vaporization at triple point (J mol^-1)
##   h_sub             molar enthalpy of sublimation at triple point (J mol^-1)
##   melting_slope     Clausius-Clapeyron melting slope, K per Pa (APPROX; small)
##   density_liquid    liquid density (kg m^-3) at/near boiling point (APPROX)
##   density_solid     solid density (kg m^-3) (APPROX)
##   role              "gas" | "greenhouse" | "solvent" | "noble"
##   notes             provenance / caveats
const _SPECIES := {
	"H2": {
		"name": "hydrogen", "Mm": 2.01588e-3,
		"t_triple": 13.8, "p_triple": 7.04e3, "t_crit": 33.19, "p_crit": 1.29e6,
		"t_boil": 20.28,
		"h_fus": 117.0, "h_vap": 904.0, "h_sub": 1021.0,
		"melting_slope": 2.5e-8, "density_liquid": 70.8, "density_solid": 87.0,
		"role": "gas", "notes": "CRC: triple 13.8K/7.04kPa, crit 33.19K/1.29MPa.",
	},
	"He": {
		"name": "helium", "Mm": 4.002602e-3,
		"t_triple": null, "p_triple": null, "t_crit": 5.195, "p_crit": 0.227e6,
		"t_boil": 4.222,
		"h_fus": null, "h_vap": 83.0, "h_sub": null,
		"melting_slope": 0.0, "density_liquid": 125.0, "density_solid": null,
		"role": "noble", "notes": "No low-pressure solid—liquid exists; treated as gas in the modelled P/T range (solid requires >~25 bar && <1K).",
	},
	"N2": {
		"name": "nitrogen", "Mm": 28.0134e-3,
		"t_triple": 63.15, "p_triple": 12.53e3, "t_crit": 126.19, "p_crit": 3.39e6,
		"t_boil": 77.36,
		"h_fus": 720.0, "h_vap": 5570.0, "h_sub": 6290.0,
		"melting_slope": 1.9e-8, "density_liquid": 808.0, "density_solid": 1026.0,
		"role": "gas", "notes": "CRC/NIST standard triple (63.15K, 12.53kPa) and critical (126.2K, 3.39MPa).",
	},
	"O2": {
		"name": "oxygen", "Mm": 31.998e-3,
		"t_triple": 54.36, "p_triple": 1.46e2, "t_crit": 154.58, "p_crit": 5.04e6,
		"t_boil": 90.19,
		"h_fus": 444.0, "h_vap": 6820.0, "h_sub": 7264.0,
		"melting_slope": 3.0e-8, "density_liquid": 1141.0, "density_solid": 1513.0,
		"role": "gas", "notes": "CRC/NIST standard triple (54.36K, 0.146kPa) and critical (154.6K, 5.04MPa).",
	},
	"CO": {
		"name": "carbon monoxide", "Mm": 28.0101e-3,
		"t_triple": 68.15, "p_triple": 15.35e3, "t_crit": 132.91, "p_crit": 3.49e6,
		"t_boil": 81.65,
		"h_fus": 836.0, "h_vap": 6044.0, "h_sub": 6880.0,
		"melting_slope": 2.5e-8, "density_liquid": 790.0, "density_solid": 923.0,
		"role": "gas", "notes": "CRC/NIST standard triple/critical values.",
	},
	"CO2": {
		"name": "carbon dioxide", "Mm": 44.009e-3,
		"t_triple": 216.59, "p_triple": 5.1795e5, "t_crit": 304.13, "p_crit": 7.377e6,
		"t_boil": null,
		"h_fus": 8.9e3, "h_vap": 16.3e3, "h_sub": 25.2e3,
		"melting_slope": 8.0e-8, "density_liquid": 710.0, "density_solid": 1562.0,
		"role": "gas", "notes": "No liquid below 5.18 bar. Triple 216.59K/0.518MPa, crit 304.13K/7.377MPa (NIST). h_sub measured; h_fus/h_vap at triple approximate.",
	},
	"CH4": {
		"name": "methane", "Mm": 16.043e-3,
		"t_triple": 90.69, "p_triple": 11.7e3, "t_crit": 190.56, "p_crit": 4.60e6,
		"t_boil": 111.66,
		"h_fus": 940.0, "h_vap": 8190.0, "h_sub": 9130.0,
		"melting_slope": 2.7e-8, "density_liquid": 422.0, "density_solid": 494.0,
		"role": "gas", "notes": "CRC/NIST standard triple (90.69K, 11.7kPa) and critical (190.6K, 4.6MPa).",
	},
	"NH3": {
		"name": "ammonia", "Mm": 17.031e-3,
		"t_triple": 195.42, "p_triple": 6.06e3, "t_crit": 405.55, "p_crit": 11.28e6,
		"t_boil": 239.8,
		"h_fus": 5.66e3, "h_vap": 23.35e3, "h_sub": 29.31e3,
		"melting_slope": 3.2e-8, "density_liquid": 682.0, "density_solid": 817.0,
		"role": "gas", "notes": "CRC/NIST standard triple (195.42K, 6.06kPa) and critical (405.6K, 11.3MPa).",
	},
	"SO2": {
		"name": "sulfur dioxide", "Mm": 64.066e-3,
		"t_triple": 197.69, "p_triple": 1.67e3, "t_crit": 430.75, "p_crit": 7.88e6,
		"t_boil": 263.13,
		"h_fus": 7.40e3, "h_vap": 24.94e3, "h_sub": 32.34e3,
		"melting_slope": 4.0e-8, "density_liquid": 1380.0, "density_solid": 1830.0,
		"role": "gas", "notes": "CRC/NIST standard triple (197.7K, 1.67kPa) and critical (430.8K, 7.88MPa).",
	},
	"H2O": {
		"name": "water", "Mm": 18.01528e-3,
		"t_triple": 273.16, "p_triple": 611.657, "t_crit": 647.096, "p_crit": 22.064e6,
		"t_boil": 373.124,
		"h_fus": 6.01e3, "h_vap": 44.02e3, "h_sub": 51.06e3,
		"melting_slope": -7.5e-8, "density_liquid": 997.0, "density_solid": 917.0,
		"role": "solvent", "notes": "NIST/CRC standard; h_sub at 273K; anomalous melting slope (ice denser than liquid). Ice polymorphs (II..X, superionic) not yet modelled.",
	},
	"Ar": {
		"name": "argon", "Mm": 39.948e-3,
		"t_triple": 83.81, "p_triple": 6.89e4, "t_crit": 150.69, "p_crit": 4.86e6,
		"t_boil": 87.30,
		"h_fus": 1.18e3, "h_vap": 6.43e3, "h_sub": 7.61e3,
		"melting_slope": 2.2e-8, "density_liquid": 1390.0, "density_solid": 1620.0,
		"role": "noble", "notes": "CRC/NIST standard triple/critical values.",
	},
}

static func symbols() -> Array:
	return _SPECIES.keys()

static func count() -> int:
	return _SPECIES.size()

static func has(sym: String) -> bool:
	return _SPECIES.has(sym)

static func get_species(sym: String) -> Dictionary:
	return _SPECIES[sym]

static func molar_mass(sym: String) -> float:
	return _SPECIES[sym]["Mm"]

static func display_name(sym: String) -> String:
	return _SPECIES[sym]["name"]

static func has_triple(sym: String) -> bool:
	return _SPECIES[sym]["t_triple"] != null

static func has_critical(sym: String) -> bool:
	return _SPECIES[sym]["t_crit"] != null

static func triple_temperature(sym: String) -> float:
	return _SPECIES[sym]["t_triple"]

static func triple_pressure(sym: String) -> float:
	return _SPECIES[sym]["p_triple"]

static func critical_temperature(sym: String) -> float:
	return _SPECIES[sym]["t_crit"]

static func critical_pressure(sym: String) -> float:
	return _SPECIES[sym]["p_crit"]

static func h_fusion(sym: String) -> float:
	return _SPECIES[sym]["h_fus"]

static func h_vaporization(sym: String) -> float:
	return _SPECIES[sym]["h_vap"]

static func h_sublimation(sym: String) -> float:
	return _SPECIES[sym]["h_sub"]

static func melting_slope_k_per_pa(sym: String) -> float:
	return _SPECIES[sym]["melting_slope"]

static func liquid_density(sym: String) -> float:
	return _SPECIES[sym]["density_liquid"]

static func solid_density(sym: String) -> float:
	return _SPECIES[sym]["density_solid"]

static func is_greenhouse_contributor(sym: String) -> bool:
	return sym in ["H2O", "CO2", "CH4", "NH3", "SO2", "CO", "N2", "H2"]

static func is_condensable(sym: String) -> bool:
	return _SPECIES[sym]["t_triple"] != null or _SPECIES[sym]["t_crit"] != null

static func pretty_name(sym: String) -> String:
	return _SPECIES[sym]["name"]

## Provenance report.
static func provenance_report() -> String:
	var l: Array[String] = []
	l.append("## SpeciesDatabase provenance")
	l.append("Primary sources: CRC Handbook of Chemistry and Physics (101st ed.),")
	l.append("NIST Chemistry WebBook. Values marked APPROX are engineering-grade estimates;")
	l.append("vapor pressures are computed (not tabulated Antoine coefficients).")
	l.append("")
	for sym in _SPECIES.keys():
		var d: Dictionary = _SPECIES[sym]
		l.append("- %s (%s): %s" % [sym, d["name"], d["notes"]])
	return "\n".join(l)