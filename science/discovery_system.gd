# discovery_system.gd
# Elements/compounds are finite catalogues. "Materials" are continuous numeric
# signatures; sufficiently distant signatures become new discoveries.
class_name DiscoverySystem
extends RefCounted

const NOVELTY_THRESHOLD := 0.16
const KINDS := ["elements", "compounds", "materials"]

var catalogue := {"elements": {}, "compounds": {}, "materials": {}}
var material_records: Array = [] # [{id,label,fingerprint,count,first_position}]
var total_found := 0
var _last_fingerprint := {}
var _farthest := 0.0

static func fingerprint(report: Dictionary) -> Dictionary:
	var names_elements: Array = report.get("elements_mass_pct", report.get("elements", {})).keys()
	var names_compounds: Array = []
	var mineral_vector := {}
	for m in report.get("substrate", {}).get("minerals", []):
		var n := String(m.get("name", "?"))
		names_compounds.append(n)
		mineral_vector[n] = float(m.get("fraction", 0.0))
	for s in report.get("atmosphere", {}).get("species", []):
		var sym := String(s.get("symbol", "?"))
		if not names_compounds.has(sym):
			names_compounds.append(sym)

	var element_vector := {}
	for e in report.get("elements_mass_pct", report.get("elements", {})).keys():
		element_vector[e] = float(report.get("elements_mass_pct", report.get("elements", {}))[e]) / 100.0

	var surface: Dictionary = report.get("surface", {})
	var covers: Dictionary = surface.get("covers", {})
	var substrate: Dictionary = report.get("substrate", {})
	var phase_vector := {
		"liquid": float(covers.get("liquid", 0.0)),
		"frost": float(covers.get("frost", 0.0)),
		"sediment": float(covers.get("sediment", 0.0)),
		"organic": float(covers.get("organic", 0.0)),
		"vegetation": float(covers.get("vegetation", 0.0)),
	}
	var texture := {
		"porosity": float(substrate.get("porosity", 0.0)),
		"grain_size_m": float(substrate.get("grain_size_mean_m", 1.0e-3)),
		"weathering": float(substrate.get("weathering_index", 0.0)),
		"oxidation": float(substrate.get("oxidation_index", 0.0)),
		"hydration": float(substrate.get("hydration_index", 0.0)),
	}
	var environment := {
		"temperature_k": float(report.get("temperature", 0.0)),
		"pressure_pa": float(report.get("pressure", 0.0)),
	}

	return {
		# Compatibility/name sets:
		"elements": names_elements,
		"compounds": names_compounds,
		"materials": [String(report.get("classification", "unclassified"))],
		# Quantitative identity:
		"element_vector": element_vector,
		"mineral_vector": mineral_vector,
		"phase_vector": phase_vector,
		"texture": texture,
		"environment": environment,
	}

func process(report: Dictionary) -> Dictionary:
	var fp := fingerprint(report)
	var new_items: Array = []

	for name in fp["elements"]:
		if not catalogue["elements"].has(name):
			catalogue["elements"][name] = 0
			new_items.append({"kind": "elements", "name": name})
			total_found += 1
		catalogue["elements"][name] += 1

	for name in fp["compounds"]:
		if not catalogue["compounds"].has(name):
			catalogue["compounds"][name] = 0
			new_items.append({"kind": "compounds", "name": name})
			total_found += 1
		catalogue["compounds"][name] += 1

	var nearest_idx := -1
	var nearest_distance := INF
	for i in range(material_records.size()):
		var d := fingerprint_distance(material_records[i]["fingerprint"], fp)
		if d < nearest_distance:
			nearest_distance = d
			nearest_idx = i

	var material_new := material_records.is_empty() or nearest_distance >= NOVELTY_THRESHOLD
	var signature_id := ""
	if material_new:
		var seq := material_records.size() + 1
		signature_id = "MAT-%06d" % seq
		var label := String(report.get("classification", "unclassified material"))
		var display_key := "%s · %s" % [label, signature_id]
		material_records.append({
			"id": signature_id,
			"label": label,
			"display_key": display_key,
			"fingerprint": fp.duplicate(true),
			"count": 1,
			"first_position": report.get("position", Vector2.ZERO),
		})
		catalogue["materials"][display_key] = 1
		new_items.append({"kind": "materials", "name": label, "signature_id": signature_id})
		total_found += 1
		if nearest_distance == INF:
			nearest_distance = 1.0
	else:
		var rec: Dictionary = material_records[nearest_idx]
		rec["count"] = int(rec.get("count", 0)) + 1
		material_records[nearest_idx] = rec
		signature_id = String(rec["id"])
		catalogue["materials"][rec["display_key"]] = rec["count"]

	var step_distance := 0.0
	if not _last_fingerprint.is_empty():
		step_distance = fingerprint_distance(_last_fingerprint, fp)
	_farthest = maxf(_farthest, step_distance)
	_last_fingerprint = fp.duplicate(true)

	return {
		"new": new_items,
		"distance": step_distance,
		"novelty_distance": nearest_distance,
		"material_new": material_new,
		"material_signature": signature_id,
		"fingerprint": fp,
		"total": total_found,
	}

static func fingerprint_distance(a: Dictionary, b: Dictionary) -> float:
	var d_elements := _dict_l1(a.get("element_vector", {}), b.get("element_vector", {})) * 0.5
	var d_minerals := _dict_l1(a.get("mineral_vector", {}), b.get("mineral_vector", {})) * 0.5
	var d_phases := _dict_l1(a.get("phase_vector", {}), b.get("phase_vector", {})) * 0.5

	var ta: Dictionary = a.get("texture", {})
	var tb: Dictionary = b.get("texture", {})
	var grain_a := log(maxf(float(ta.get("grain_size_m", 1.0e-9)), 1.0e-9))
	var grain_b := log(maxf(float(tb.get("grain_size_m", 1.0e-9)), 1.0e-9))
	var d_texture := 0.0
	d_texture += absf(float(ta.get("porosity", 0.0)) - float(tb.get("porosity", 0.0)))
	d_texture += clampf(absf(grain_a - grain_b) / 10.0, 0.0, 1.0)
	d_texture += absf(float(ta.get("weathering", 0.0)) - float(tb.get("weathering", 0.0)))
	d_texture += absf(float(ta.get("oxidation", 0.0)) - float(tb.get("oxidation", 0.0)))
	d_texture += absf(float(ta.get("hydration", 0.0)) - float(tb.get("hydration", 0.0)))
	d_texture /= 5.0

	var ea: Dictionary = a.get("environment", {})
	var eb: Dictionary = b.get("environment", {})
	var t1 := maxf(float(ea.get("temperature_k", 1.0)), 1.0)
	var t2 := maxf(float(eb.get("temperature_k", 1.0)), 1.0)
	var p1 := maxf(float(ea.get("pressure_pa", SciConstants.MIN_PRESSURE_PA)), SciConstants.MIN_PRESSURE_PA)
	var p2 := maxf(float(eb.get("pressure_pa", SciConstants.MIN_PRESSURE_PA)), SciConstants.MIN_PRESSURE_PA)
	var d_env := 0.5 * clampf(absf(log(t1 / t2)) / 2.5, 0.0, 1.0) 		+ 0.5 * clampf(absf(log(p1 / p2)) / 12.0, 0.0, 1.0)

	return clampf(
		0.34 * d_elements +
		0.32 * d_minerals +
		0.14 * d_phases +
		0.12 * d_texture +
		0.08 * d_env, 0.0, 1.0)

static func _dict_l1(a: Dictionary, b: Dictionary) -> float:
	var keys := {}
	for k in a.keys():
		keys[k] = true
	for k in b.keys():
		keys[k] = true
	var total := 0.0
	for k in keys.keys():
		total += absf(float(a.get(k, 0.0)) - float(b.get(k, 0.0)))
	return total

func summary() -> Dictionary:
	return {
		"elements": catalogue["elements"].size(),
		"compounds": catalogue["compounds"].size(),
		"materials": material_records.size(),
		"total": total_found,
		"farthest_distance": _farthest,
		"novelty_threshold": NOVELTY_THRESHOLD,
	}


func export_state() -> Dictionary:
	var records: Array = []
	for record in material_records:
		var p: Vector2 = record.get("first_position", Vector2.ZERO)
		var clean := record.duplicate(true) as Dictionary
		clean["first_position"] = [p.x, p.y]
		records.append(clean)
	return {
		"catalogue": catalogue.duplicate(true),
		"material_records": records,
		"total_found": total_found,
		"farthest_distance": _farthest,
	}

func import_state(data: Dictionary) -> void:
	catalogue = data.get("catalogue", {"elements": {}, "compounds": {}, "materials": {}}).duplicate(true)
	for kind in KINDS:
		if not catalogue.has(kind):
			catalogue[kind] = {}
	material_records.clear()
	for stored in data.get("material_records", []):
		var record: Dictionary = stored.duplicate(true)
		var p = record.get("first_position", [0.0, 0.0])
		if p is Array and p.size() >= 2:
			record["first_position"] = Vector2(float(p[0]), float(p[1]))
		else:
			record["first_position"] = Vector2.ZERO
		material_records.append(record)
	total_found = int(data.get("total_found",
		catalogue["elements"].size() + catalogue["compounds"].size() + material_records.size()))
	_farthest = float(data.get("farthest_distance", 0.0))
	_last_fingerprint = {}
