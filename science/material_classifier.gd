# material_classifier.gd
# Human-readable names are derived from quantitative state. Identity is NOT the
# name: DiscoverySystem uses the full numeric material fingerprint.
class_name MaterialClassifier
extends RefCounted

const FROST_THRESHOLD := 0.40
const LIQUID_THRESHOLD := 0.50
const SEDIMENT_THRESHOLD := 0.50

static func classify(surface: SurfaceState, substrate: SubstrateState,
		thermal: ThermalState, sediment: Dictionary) -> Dictionary:
	var kind := "bedrock"
	var noun := "bedrock"
	var materials: Array = []

	if surface.liquid_cover >= LIQUID_THRESHOLD:
		kind = "liquid"
		noun = "%s liquid surface" % SpeciesDatabase.pretty_name(surface.liquid_species)
	elif surface.frost_cover >= FROST_THRESHOLD:
		kind = "frost"
		noun = "%s frost plain" % SpeciesDatabase.pretty_name(surface.frost_species)
	elif surface.vegetation_cover >= 0.15:
		kind = "biogenic"
		noun = "vegetated regolith"
	elif surface.sediment_cover >= SEDIMENT_THRESHOLD:
		kind = "sediment"
		noun = "%s sediment" % String(sediment.get("kind", "mixed"))
	elif surface.salt_cover >= 0.30:
		kind = "evaporite"
		noun = "evaporite crust"

	var modifiers: Array[String] = []
	if substrate.oxidation_index >= 0.35:
		modifiers.append("oxidized")
	elif substrate.oxidation_index >= 0.12:
		modifiers.append("ferruginous")
	if substrate.hydration_index >= 0.5:
		modifiers.append("hydrated")
	if surface.organic_cover >= 0.30 and surface.vegetation_cover < 0.15:
		modifiers.append("organic-rich")
	if substrate.elemental_mass_fraction.get("C", 0.0) >= 0.10:
		modifiers.append("carbon-rich")
	if substrate.porosity >= 0.50:
		modifiers.append("high-porosity")
	if thermal.temperature > 1200.0:
		modifiers.append("thermally-altered")

	var mineral_names := _dominant_mineral_names(substrate, 2)
	var mineral_phrase := ""
	if not mineral_names.is_empty() and kind not in ["liquid", "frost"]:
		mineral_phrase = "-".join(mineral_names)

	var parts: Array[String] = []
	parts.append_array(modifiers)
	if mineral_phrase != "":
		parts.append(mineral_phrase)
	parts.append(noun)
	var label := " ".join(parts)
	if label == "":
		label = "unclassified planetary material"

	_append_materials(materials, surface, substrate, sediment)
	return {
		"label": label,
		"kind": kind,
		"short": _short_code(kind, substrate),
		"materials": materials,
		"modifiers": modifiers,
		"dominant_minerals": mineral_names,
	}

static func _dominant_mineral_names(substrate: SubstrateState, count: int) -> Array[String]:
	var out: Array[String] = []
	for m in substrate.bedrock_minerals:
		if out.size() >= count:
			break
		if float(m.get("fraction", 0.0)) < 0.08:
			continue
		var n := String(m.get("name", ""))
		n = n.split(" ")[0].to_lower()
		if n != "" and not out.has(n):
			out.append(n)
	return out

static func _append_materials(materials: Array, surface: SurfaceState,
		substrate: SubstrateState, sediment: Dictionary) -> void:
	for m in substrate.bedrock_minerals:
		if float(m.get("fraction", 0.0)) > 0.005:
			materials.append({"label": m.get("name", "?"), "fraction": m.get("fraction", 0.0), "kind": "mineral"})
	if surface.sediment_cover > 0.01:
		materials.append({"label": "%s sediment" % sediment.get("kind", "mixed"),
			"fraction": surface.sediment_cover, "kind": "sediment"})
	if surface.liquid_cover > 0.01 and surface.liquid_species != "":
		materials.append({"label": "liquid %s" % surface.liquid_species,
			"fraction": surface.liquid_cover, "kind": "liquid"})
	if surface.frost_cover > 0.01 and surface.frost_species != "":
		materials.append({"label": "%s frost" % surface.frost_species,
			"fraction": surface.frost_cover, "kind": "frost"})
	if surface.organic_cover > 0.01:
		materials.append({"label": "organic matter", "fraction": surface.organic_cover, "kind": "organic"})
	if surface.vegetation_cover > 0.01:
		materials.append({"label": "biogenic cover", "fraction": surface.vegetation_cover, "kind": "biogenic"})

static func _short_code(kind: String, substrate: SubstrateState) -> String:
	var top := substrate.dominant_mineral().split(" ")[0].to_upper()
	return "%s/%s" % [kind.to_upper(), top.left(8)]
