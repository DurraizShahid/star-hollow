# equilibrium_solver.gd
# -----------------------------------------------------------------------------
# Simplified CIPW-style normative mineral allocation from rock chemistry.
#
# Converts a bulk rock elemental budget (MASS FRACTIONS, kg element / kg rock)
# into a mineral assemblage. Work happens in MOLES so that element conservation
# is exact by construction: each mineral template lists the moles of each
# element per formula unit, and consumed mineral mass = q * M_mineral.
#
# Fidelity: SIMPLIFIED_PHYSICAL -- template stoichiometry is real mineral
# chemistry, but the allocation ORDER is normative (deterministic), not a full
# Gibbs free-energy minimization. dG_f298 is used only to choose competing
# forms (e.g. anhydrite vs hydrated gypsum).
#
# Volatile ices (H2O/CO2/CH4 frosts, liquid oceans) are NOT allocated here;
# the surface/phase solver decides them from P-T.
# -----------------------------------------------------------------------------
class_name EquilibriumSolver
extends RefCounted

const MIN_Q := 1.0e-9

## Mol budget per element per kg rock.
static func _moles(element_mass_fraction: Dictionary) -> Dictionary:
	var b := {}
	for e in element_mass_fraction.keys():
		var frac: float = element_mass_fraction[e]
		if frac > 0.0 and ElementDatabase.has_symbol(e):
			b[e] = frac / ElementDatabase.mass_kg_per_mol(e)   # mol per kg rock
	return b

## Template: name -> { stoich: {sym: mol_per_formula}, molar: g/mol, uses_oxygen: bool }
const TEMPLATES := {
	"Apatite Ca5(PO4)3(OH)": { "stoich": { "Ca": 5, "P": 3, "O": 13 }, "molar": 502.3 },
	"Pyrite FeS2": { "stoich": { "Fe": 1, "S": 2 }, "molar": 119.98 },
	"Halite NaCl": { "stoich": { "Na": 1, "Cl": 1 }, "molar": 58.44 },
	"Ilmenite FeTiO3": { "stoich": { "Fe": 1, "Ti": 1, "O": 3 }, "molar": 151.7 },
	"Magnetite Fe3O4": { "stoich": { "Fe": 3, "O": 4 }, "molar": 231.5 },
	"Hematite Fe2O3": { "stoich": { "Fe": 2, "O": 3 }, "molar": 159.7 },
	"Cementite Fe3C": { "stoich": { "Fe": 3, "C": 1 }, "molar": 179.25 },
	"Graphite C": { "stoich": { "C": 1 }, "molar": 12.011 },
	"K-Feldspar KAlSi3O8": { "stoich": { "K": 1, "Al": 1, "Si": 3, "O": 8 }, "molar": 278.33 },
	"Albite NaAlSi3O8": { "stoich": { "Na": 1, "Al": 1, "Si": 3, "O": 8 }, "molar": 262.22 },
	"Anorthite CaAl2Si2O8": { "stoich": { "Ca": 1, "Al": 2, "Si": 2, "O": 8 }, "molar": 278.21 },
	"Diopside CaMgSi2O6": { "stoich": { "Ca": 1, "Mg": 1, "Si": 2, "O": 6 }, "molar": 216.55 },
	"Enstatite MgSiO3": { "stoich": { "Mg": 1, "Si": 1, "O": 3 }, "molar": 100.39 },
	"Forsterite Mg2SiO4": { "stoich": { "Mg": 2, "Si": 1, "O": 4 }, "molar": 140.69 },
	"Fayalite Fe2SiO4": { "stoich": { "Fe": 2, "Si": 1, "O": 4 }, "molar": 203.77 },
	"Quartz SiO2": { "stoich": { "Si": 1, "O": 2 }, "molar": 60.08 },
	"Corundum Al2O3": { "stoich": { "Al": 2, "O": 3 }, "molar": 101.96 },
	"Calcite CaCO3": { "stoich": { "Ca": 1, "C": 1, "O": 3 }, "molar": 100.09 },
	"Anhydrite CaSO4": { "stoich": { "Ca": 1, "S": 1, "O": 4 }, "molar": 136.14 },
	"Gypsum CaSO4.2H2O": { "stoich": { "Ca": 1, "S": 1, "O": 4 }, "molar": 172.17 },
}

## Main entry.
## element_mass_fraction: {symbol: kg_element/kg_rock}
## context: { crust, hydrated (bool), carbonate_pressure (Pa), confidence }
static func norm(element_mass_fraction: Dictionary, context: Dictionary = {}) -> Dictionary:
	var budget := _moles(element_mass_fraction)     # mol of each element / kg rock
	var consumed := {}                                # sym -> mol consumed (for audit)
	for e in budget.keys():
		consumed[e] = 0.0

	var minerals: Array = []
	var notes: Array = []

	# ---- 1. Apatite: P with Ca -----------------------------------------
	var q := _q_for("Apatite Ca5(PO4)3(OH)", budget)
	_take_template_q("Apatite Ca5(PO4)3(OH)", budget, consumed, minerals, q)

	# ---- 2. Pyrite: S with Fe -------------------------------------------
	q = _q_for("Pyrite FeS2", budget)
	_take_template_q("Pyrite FeS2", budget, consumed, minerals, q)

	# ---- 3. Halite: Cl with Na ------------------------------------------
	q = _q_for("Halite NaCl", budget)
	_take_template_q("Halite NaCl", budget, consumed, minerals, q)

	# ---- 4. Ilmenite: Ti with Fe ----------------------------------------
	q = _q_for("Ilmenite FeTiO3", budget)
	_take_template_q("Ilmenite FeTiO3", budget, consumed, minerals, q)

	# ---- 5. Carbon: carbide in metallic crust, else graphite -------------
	var crust_style: String = context.get("crust", "felsic")
	if crust_style == "metallic":
		q = _q_for("Cementite Fe3C", budget)
		_take_template_q("Cementite Fe3C", budget, consumed, minerals, q)
	q = _q_for("Graphite C", budget)
	_take_template_q("Graphite C", budget, consumed, minerals, q)

	# ---- 6. Feldspars (norm order: K-first, then albite, then anorthite) --
	q = _q_for("K-Feldspar KAlSi3O8", budget)
	_take_template_q("K-Feldspar KAlSi3O8", budget, consumed, minerals, q)
	q = _q_for("Albite NaAlSi3O8", budget)
	_take_template_q("Albite NaAlSi3O8", budget, consumed, minerals, q)
	var si_after_feld := _mol("Si", budget)
	# Anorthite only consumes Si that will not starve later phases too badly;
	# clamp Si consumption so some Si remains for pyroxene/olivine/quartz.
	var max_anorth_si := si_after_feld * 0.45
	if max_anorth_si > 0.0:
		q = minf(_q_for("Anorthite CaAl2Si2O8", budget), max_anorth_si / 2.0)
		_take_template_q("Anorthite CaAl2Si2O8", budget, consumed, minerals, q)

	# ---- 7. Pyroxenes: Ca-Mg diopside -> Mg enstatite --------------------
	q = _q_for("Diopside CaMgSi2O6", budget)
	_take_template_q("Diopside CaMgSi2O6", budget, consumed, minerals, q)
	q = _q_for("Enstatite MgSiO3", budget)
	_take_template_q("Enstatite MgSiO3", budget, consumed, minerals, q)

	# ---- 8. Olivine (Mg + Fe filling leftover Si) -------------------------
	var fe_mol := _mol("Fe", budget)
	var mg_mol := _mol("Mg", budget)
	var si_mol := _mol("Si", budget)
	var forsterite_q := minf(mg_mol / 2.0, si_mol)
	var rem_si := si_mol - forsterite_q
	var fayalite_q := minf(fe_mol / 2.0, rem_si)
	_take_template_q("Forsterite Mg2SiO4", budget, consumed, minerals, forsterite_q)
	_take_template_q("Fayalite Fe2SiO4", budget, consumed, minerals, fayalite_q)

	# ---- 9. Corundum: leftover Al ----------------------------------------
	q = _q_for("Corundum Al2O3", budget)
	_take_template_q("Corundum Al2O3", budget, consumed, minerals, q)

	# ---- 10. Quartz: leftover Si ------------------------------------------
	q = _q_for("Quartz SiO2", budget)
	_take_template_q("Quartz SiO2", budget, consumed, minerals, q)

	# ---- 11. Sulfates / carbonates for leftover Ca -----------------------
	var ca_mol := _mol("Ca", budget)
	var s_mol := _mol("S", budget)
	var hydrated: bool = context.get("hydrated", false)
	if ca_mol > MIN_Q:
		if s_mol > MIN_Q:
			var sulfate_q := minf(ca_mol, s_mol)
			var which := "Gypsum CaSO4.2H2O" if hydrated else "Anhydrite CaSO4"
			# dG_f298 ranking: hydrated form stable only when water present.
			if which == "Gypsum CaSO4.2H2O" and not context.get("has_liquid_water", false):
				which = "Anhydrite CaSO4"
				notes.append("gypsum suppressed (no liquid water)")
			_take_template_q(which, budget, consumed, minerals, sulfate_q)
			notes.append("sulfate from leftover Ca")
		else:
			var c_mol := _mol("C", budget)
			if c_mol > MIN_Q and context.get("carbonate_pressure", 0.0) > 0.0:
				var carb_q := minf(ca_mol, c_mol)
				_take_template_q("Calcite CaCO3", budget, consumed, minerals, carb_q)
				notes.append("carbonate from leftover Ca + CO2")

	# ---- 12. Leftover Fe -> hematite (oxidation product) ------------------
	q = _q_for("Hematite Fe2O3", budget)
	_take_template_q("Hematite Fe2O3", budget, consumed, minerals, q)
	if q > MIN_Q:
		notes.append("oxidative norm")

	# ---- 13. Residue (elemental leftovers) --------------------------------
	var leftover := {}
	for e in budget.keys():
		var v: float = budget[e]
		if v > MIN_Q:
			leftover[e] = v * ElementDatabase.mass_kg_per_mol(e)  # kg/kg rock

	# Assemble output: total mass = consumed mineral masses + residue.
	var mineral_masses := {}
	var total := 0.0
	for m in minerals:
		mineral_masses[m["name"]] = m["mass"]
		total += m["mass"]
	for e in leftover.keys():
		total += leftover[e]

	var out_minerals: Array = []
	for m in minerals:
		out_minerals.append({
			"name": m["name"],
			"fraction": m["mass"] / total if total > 0.0 else 0.0,
			"conf": context.get("confidence", "norm"),
		})
	out_minerals.sort_custom(func(a, b): return a["fraction"] > b["fraction"])
	return {
		"minerals": out_minerals,
		"mineral_mass_kg": mineral_masses,
		"total_mass_kg": total,
		"residue": leftover,
		"consumed_mol": consumed,
		"notes": notes,
		"budget_mol": _moles(element_mass_fraction),
	}

# ---- helpers -------------------------------------------------------------
static func _mol(sym: String, budget: Dictionary) -> float:
	return budget.get(sym, 0.0)

## Maximum quantity (formula units) of a template allowed by the budget.
static func _q_for(tname: String, budget: Dictionary) -> float:
	var t: Dictionary = TEMPLATES[tname]
	var q := 1e308
	for e in t["stoich"].keys():
		var need: float = t["stoich"][e]
		if need > 0.0:
			q = minf(q, _mol(e, budget) / need)
	return q if q < 1e300 else 0.0

static func _take_template_q(tname: String, budget: Dictionary, consumed: Dictionary, minerals: Array, q_formula: float) -> void:
	if q_formula <= MIN_Q:
		return
	var t: Dictionary = TEMPLATES[tname]
	var mass := 0.0
	for e in t["stoich"].keys():
		var need: float = t["stoich"][e]
		var take := q_formula * need
		budget[e] = _mol(e, budget) - take
		consumed[e] = consumed.get(e, 0.0) + take
		mass += take * ElementDatabase.mass_kg_per_mol(e)
	minerals.append({
		"name": tname,
		"mass": mass,
	})