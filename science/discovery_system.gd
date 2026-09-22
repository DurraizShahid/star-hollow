# discovery_system.gd
# -----------------------------------------------------------------------------
# Discovery catalogue with fingerprint-distance tracking.
#
# A report's fingerprint is the SET of discovered names it carries, split into
# three kinds: elements, compounds (species/minerals), materials (labels).
# A new report is considered a *discovery* when its fingerprint introduces at
# least one previously-unseen name; the catalogue marks first-seen entries. The
# gameplay "distance travelled between discoveries" uses a Jaccard-style
# fingerprint distance, seeded from the last two packets.
# -----------------------------------------------------------------------------
class_name DiscoverySystem
extends RefCounted

const KINDS := ["elements", "compounds", "materials"]

var catalogue := {
	"elements": {},
	"compounds": {},
	"materials": {},
}
var total_found := 0
var _last_fingerprint := {}
var _farthest := 0.0

## Extract the fingerprint set from a report.
static func fingerprint(report: Dictionary) -> Dictionary:
	var fp := { "elements": [], "compounds": [], "materials": [] }
	var elements: Dictionary = report.get("elements", {})
	for e in elements.keys():
		fp["elements"].append(e)
	var substrate: Dictionary = report.get("substrate", {})
	for m in substrate.get("minerals", []):
		fp["compounds"].append(m["name"])
	var atm: Dictionary = report.get("atmosphere", {})
	for s in atm.get("species", []):
		fp["compounds"].append(s["symbol"])
	var surface: Dictionary = report.get("surface", {})
	var ms: Array = surface.get("materials", [])
	for mm in ms:
		fp["materials"].append(mm["label"])
	return fp

## Feed a report into the catalogue.
## Returns { "new": [{kind, name}...], "distance": float, "total": int }
func process(report: Dictionary) -> Dictionary:
	var fp := fingerprint(report)
	var new_items: Array = []
	for kind in KINDS:
		for name in fp[kind]:
			if not catalogue[kind].has(name):
				catalogue[kind][name] = 0
		for name in fp[kind]:
			catalogue[kind][name] = catalogue[kind][name] + 1
			if catalogue[kind][name] == 1:
				new_items.append({ "kind": kind, "name": name })
				total_found += 1

	var dist := 0.0
	if not _last_fingerprint.is_empty():
		dist = fingerprint_distance(_last_fingerprint, fp)
	_farthest = maxf(_farthest, dist)
	_last_fingerprint = fp
	return { "new": new_items, "distance": dist, "total": total_found }

static func fingerprint_distance(a: Dictionary, b: Dictionary) -> float:
	var set_a := {}
	var set_b := {}
	for kind in KINDS:
		for n in a[kind]:
			set_a[n] = true
		for n in b[kind]:
			set_b[n] = true
	var a_names := set_a.keys()
	var b_names := set_b.keys()
	if a_names.is_empty() and b_names.is_empty():
		return 0.0
	var intersection := 0
	for n in a_names:
		if set_b.has(n):
			intersection += 1
	var union := a_names.size() + b_names.size() - intersection
	return 1.0 - float(intersection) / maxf(float(union), 1.0)

func summary() -> Dictionary:
	return {
		"elements": catalogue["elements"].size(),
		"compounds": catalogue["compounds"].size(),
		"materials": catalogue["materials"].size(),
		"total": total_found,
		"farthest_distance": _farthest,
	}