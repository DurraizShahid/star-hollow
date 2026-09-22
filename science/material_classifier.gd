# material_classifier.gd
# -----------------------------------------------------------------------------
# Translates resolved physical state into a scientific material classification
# using QUANTITATIVE THRESHOLDS -- never "this pixel looks dark, call it iron".
# Every branch is a number comparison on cover fractions, temperature, mineral
# identity, etc. Output labels feed the HUD, probe report and discovery catalogue.
# -----------------------------------------------------------------------------
class_name MaterialClassifier
extends RefCounted

const FROST_THRESHOLD := 0.40
const LIQUID_THRESHOLD := 0.50
const SEDIMENT_THRESHOLD := 0.50
const ORGANIC_THRESHOLD := 0.35

## Returns { label, kind, short, materials: [ {label, fraction, kind} ] }
static func classify(surface: SurfaceState, substrate: SubstrateState,
		thermal: ThermalState, sediment: Dictionary) -> Dictionary:
	var m := {}
	var materials: Array = []

	# 1. Liquid (stable condensed volatile).
	if surface.liquid_cover >= LIQUID_THRESHOLD:
		var s := surface.liquid_species
		var name := SpeciesDatabase.pretty_name(s)
		m = { "label": "Ocean of %s" % name, "kind": "liquid", "short": s }
		materials.append({ "label": "liquid %s" % s, "fraction": surface.liquid_cover, "kind": "liquid" })

	# 2. Frost / ice plain.
	elif surface.frost_cover >= FROST_THRESHOLD:
		var s := surface.frost_species
		var name := SpeciesDatabase.pretty_name(s)
		m = { "label": "%s frost %s" % [name, "plain"], "kind": "frost", "short": s }
		materials.append({ "label": "%s frost" % s, "fraction": surface.frost_cover, "kind": "frost" })

	# 3. Organic-rich soil / tholin.
	elif surface.organic_cover >= ORGANIC_THRESHOLD:
		m = { "label": "tholin plain", "kind": "organic", "short": "THOLIN" }
		materials.append({ "label": "organic soil", "fraction": surface.organic_cover, "kind": "organic" })

	# 4. Sediment-covered.
	elif surface.sediment_cover >= SEDIMENT_THRESHOLD:
		var kind: String = sediment.get("kind", "sand")
		var label: String = {
			"dune": "aeolian dune field", "sand": "sandy plain", "gravel": "gravel talus",
			"silt": "silt basin", "clay": "clay mudflat",
		}.get(kind, "sediment plain")
		m = { "label": label, "kind": "sediment", "short": kind.to_upper() }
		materials.append({ "label": "%s sediment" % kind, "fraction": surface.sediment_cover, "kind": "sediment" })

	# 5. Exposed bedrock.
	else:
		m = _classify_bedrock(substrate, surface, thermal)

	# Append residual materials (partial covers) for the report/catalogue.
	_append_partial(materials, surface, substrate, thermal)
	m["materials"] = materials
	return m

static func _classify_bedrock(substrate: SubstrateState, surface: SurfaceState, thermal: ThermalState) -> Dictionary:
	var top := substrate.dominant_mineral()
	var crust := substrate.crust_style
	var label := ""
	var kind := "rock"
	var short := ""
	var oxidized: bool = substrate.normative_notes.has("oxidative norm") or float(substrate.residue.get("Fe", 0.0)) > 1.0e-4

	var base: Variant = {
		"mafic": ["Basaltic plain", "BASALT", "mafic_bedrock"],
		"felsic": ["Felsic highland", "FELSIC", "felsic_bedrock"],
		"metallic": ["Metallic exposure", "METAL", "metallic_bedrock"],
		"carbonaceous": ["Carbon-rich crust", "CARBON", "carbon_bedrock"],
		"evaporitic": ["Salt flat", "SALT", "evaporite_bedrock"],
		"sedimentary": ["Sedimentary plain", "SEDIM", "sedimentary_bedrock"],
		"sediment": ["Sediment plain", "SEDIM", "sediment_bedrock"],
		"evaporite": ["Salt flat", "SALT", "evaporite_bedrock"],
		"ultramafic": ["Ultramafic crust", "ULTRAMAF", "ultramafic_bedrock"],
		"hydrothermal": ["Hydrothermal field", "HYDRO", "hydrothermal_bedrock"],
	}.get(crust, ["Unclassified crust", "UNC", "unclassified_bedrock"])
	if base:
		label = base[0]
		short = base[1]
		kind = base[2]
	# Refine by dominant mineral.
	if top.contains("Quartz"):
		label = "Quartz-crusted plain"
	elif top.contains("Olivine") or top.contains("Enstatite") or top.contains("Diopside"):
		label = "Basaltic plain"
		short = "BASALT"
		kind = "mafic_bedrock"
	# Weathering signatures.
	if oxidized:
		if thermal and thermal.temperature > 210.0:
			label = "Oxidized %s" % label.to_lower()
		short = "OXID"
	return { "label": label, "kind": kind, "short": short }

static func _append_partial(materials: Array, surface: SurfaceState, substrate: SubstrateState, thermal: ThermalState) -> void:
	if surface.liquid_cover > 0.01 and surface.liquid_species != "":
		materials.append({ "label": "liquid %s" % surface.liquid_species, "fraction": surface.liquid_cover, "kind": "liquid" })
	if surface.frost_cover > 0.01 and surface.frost_species != "":
		materials.append({ "label": "%s frost" % surface.frost_species, "fraction": surface.frost_cover, "kind": "frost" })
	if surface.organic_cover > 0.01:
		materials.append({ "label": "organic soil", "fraction": surface.organic_cover, "kind": "organic" })
	if surface.sediment_cover > 0.01:
		materials.append({ "label": "sediment", "fraction": surface.sediment_cover, "kind": "sediment" })
	if materials.is_empty():
		for min in substrate.bedrock_minerals:
			materials.append({ "label": min["name"], "fraction": min.get("fraction", 0.0), "kind": "mineral" })