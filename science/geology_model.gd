# geology_model.gd
# -----------------------------------------------------------------------------
# Spatial geological boundary-condition generation.
#
# Produces deterministic fields at absolute world coordinates (metres):
#   * elevation            (continuous topography; drives flow/pooling/lapse)
#   * province id          (cellular Voronoi sites + planet archetype weights)
#   * crust blend          (primary + secondary crust archetype fractions)
#   * fracture density, slope, gradient
#   * day/night + zonal thermal factor (=> effective local stellar flux)
#   * wind vector + speed
#   * per-element enrichment factors (bounded, smooth)
#
# IMPORTANT: noise here establishes *boundary conditions* (where is high/low,
# where is volcanic, which crustal budget dominates). It never directly encodes
# "red noise = iron". Chemistry + physics downstream decide materials.
#
# Determinism: all fields are pure functions of (x, y) plus the planet seed.
# FastNoiseLite is seeded once per planet (generator-version-locked).
# -----------------------------------------------------------------------------
class_name GeologyModel
extends RefCounted

const PROVINCE_KEYS: Array = ["craton_highlands", "volcanic", "ultramafic_massif", "impact_crater",
	"sediment_basin", "evaporite_flat", "hydrothermal", "metallic_exposure", "carbon_terrain"]

const LONGITUDE_FRACTION := 0.5

var planet: PlanetParameters
var world_seed: int

var _elev_fbm: FastNoiseLite
var _elev_mid: FastNoiseLite
var _elev_detail: FastNoiseLite
var _ridge: FastNoiseLite
var _enrich_noise: FastNoiseLite
var _channel: FastNoiseLite

var _province_weights: Dictionary = {}  # province_key -> weight (relative)
var _longitude_wrap := 20000.0
var longitude_phase := 0.0

## Per-cell bundle describing boundary conditions.
class CellBoundary:
	extends RefCounted
	var x := 0.0
	var y := 0.0
	var elevation := 0.0
	var slope := 0.0
	var gradient_x := 0.0
	var gradient_y := 0.0
	var fracture_density := 0.0
	var province_primary := "craton_highlands"
	var province_secondary := "craton_highlands"
	var province_blend := 0.0
	var crust_primary := "felsic"
	var crust_secondary := "felsic"
	var day_factor := 1.0
	var thermal_zonal := 0.5
	var flux_factor := 1.0
	var wind_speed := 1.0
	var wind_x := 1.0
	var wind_y := 0.0
	var enrichment := {}  # symbol -> factor

func _init(p: PlanetParameters, seed_value: int) -> void:
	planet = p
	world_seed = seed_value
	_longitude_wrap = PI * p.radius * 2.0 * LONGITUDE_FRACTION

	var nbase := seed_value + 101
	_elev_fbm = _make_noise(nbase + 1, 2.0, 5, 0.5, 2.0)
	_elev_mid = _make_noise(nbase + 2, 8.0, 4, 0.5, 2.0)
	_elev_detail = _make_noise(nbase + 3, 22.0, 3, 0.5, 2.0)
	_ridge = _make_noise(nbase + 4, 7.0, 4, 0.5, 2.0)
	_enrich_noise = _make_noise(nbase + 5, 6.0, 4, 0.55, 2.1)
	_channel = _make_noise(nbase + 6, 3.0, 3, 0.5, 2.0)
	longitude_phase = (seed_value % 360) * PI / 180.0

	_build_province_weights()

func _make_noise(seed: int, freq: float, octaves: int, gain: float, lacunarity: float) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq / 1000.0
	n.fractal_octaves = octaves
	n.fractal_gain = gain
	n.fractal_lacunarity = lacunarity
	return n

func _build_province_weights() -> void:
	# Planet archetype adjusts province frequency.
	var carbon_frac := 0.0
	if planet.rock_elements.has("C"):
		carbon_frac = planet.rock_elements["C"]
	var volatile_frac := planet.volatility_fraction
	_province_weights = {
		"craton_highlands": 30.0,
		"volcanic": 16.0 + min(12.0, planet.geothermal_flux * 20.0),
		"ultramafic_massif": 12.0,
		"impact_crater": 6.0,
		"sediment_basin": 12.0,
		"evaporite_flat": 4.0 + volatile_frac * 30.0,
		"hydrothermal": 3.0 + min(8.0, planet.geothermal_flux * 8.0),
		"metallic_exposure": 3.0,
		"carbon_terrain": 3.0 + max(0.0, carbon_frac - 0.01) * 800.0,
	}

## Fetch boundary conditions at absolute coordinates (metres).
func boundary_at(x: float, y: float) -> CellBoundary:
	var b := CellBoundary.new()
	b.x = x
	b.y = y
	b.elevation = _elevation(x, y)
	b.slope = _slope(x, y)
	b.gradient_x = _elevation(x + 12.0, y) - _elevation(x - 12.0, y)
	b.gradient_y = _elevation(x, y + 12.0) - _elevation(x, y - 12.0)
	b.fracture_density = clampf(0.5 + 0.5 * _ridge.get_noise_2d(x, y), 0.0, 1.0)

	var wp := _worley(x, y)
	b.province_primary = wp["p"]
	b.province_secondary = wp["s"]
	b.province_blend = wp["blend"]
	b.crust_primary = GeologyProvinces.crust_of_province(wp["p"])
	b.crust_secondary = GeologyProvinces.crust_of_province(wp["s"])

	b.day_factor = clampf(0.5 + 0.5 * cos(TAU * (fmod(x, _longitude_wrap) + _longitude_wrap) / _longitude_wrap + longitude_phase), 0.05, 1.0)
	# Zonal (latitude-like) gradient across the strip.
	var z := clampf(sin(PI * (fmod(y, 2.0 * _longitude_wrap) + 2.0 * _longitude_wrap) / (2.0 * _longitude_wrap)), -1.0, 1.0)
	b.thermal_zonal = clampf(0.5 + 0.5 * z, 0.0, 1.0)
	# Effective stellar flux factor.
	b.flux_factor = b.day_factor * (0.35 + 0.65 * b.thermal_zonal)

	var sp := (2.0 + _channel.get_noise_2d(x, y) * 2.0)
	var fast_rotator := planet.rotation_period > 0.0 and planet.rotation_period < 3.0 * 24.0 * 3600.0 and b.day_factor > 0.6
	b.wind_speed = clampf((0.5 + sp) if fast_rotator else (0.2 + 0.4 * sp), 0.1, 2.0)
	var dir := (seed_hash(x * 0.001, y * 0.001) % 360) * PI / 180.0
	# Align channels with elevation gradient lightly.
	b.wind_x = cos(dir) * 0.85 - b.gradient_x * 0.15
	b.wind_y = sin(dir) * 0.85 - b.gradient_y * 0.15
	var wl := sqrt(b.wind_x * b.wind_x + b.wind_y * b.wind_y)
	if wl > 1e-9:
		b.wind_x /= wl
		b.wind_y /= wl

	# Per-element smooth enrichment.
	var enrich := {}
	for sym in ElementDatabase.symbols():
		var h := randi_from_string(sym + str(world_seed)) % 1000 / 1000.0
		var nv := _enrich_noise.get_noise_2d(x + 4000.0 * _hash_01(sym), y + 4000.0 * _hash_02(sym))
		var f := 1.0 + 0.45 * nv * clampf(h, 0.2, 0.9)
		enrich[sym] = clampf(f, 0.55, 1.6)
	b.enrichment = enrich
	return b

## Constant-seeded pseudo-random int from a string (deterministic hash).
func seed_hash(x: float, y: float) -> int:
	var h := floori(x)
	var g := floori(y)
	var n := (int(g) * 73856093) ^ (int(h) * 19349663) ^ world_seed
	n = (n * 0x9E3779B1) >> 0
	return n & 0x7FFFFFFF

func _hash_01(sym: String) -> float:
	return float(randi_from_string(sym) % 1000) / 1000.0

func _hash_02(sym: String) -> float:
	return float(randi_from_string(sym + "_b") % 1000) / 1000.0

func randi_from_string(s: String) -> int:
	var h := 5381
	for i in s.length():
		h = ((h * 33) + int(s.unicode_at(i))) & 0x7FFFFFFF
	return h

func _elevation(x: float, y: float) -> float:
	var wt := 1000.0
	var lt := 9000.0
	var t := _elev_fbm.get_noise_2d(x / lt, y / lt)
	var m := _elev_mid.get_noise_2d(x / (lt * 0.22), y / (lt * 0.22))
	var d := 0.3 * _elev_detail.get_noise_2d(x / 260.0, y / 260.0)
	var rg := (1.0 - absf(_ridge.get_noise_2d(x / (lt * 0.3), y / (lt * 0.3)))) * 1.4
	var relief := clampf(planet.radius * 0.0024, 300.0, 16000.0)
	var elev := t * 0.55 * relief + rg * relief * 0.5 * maxf(0.0, t) + m * relief * 0.22 + d * 60.0
	# Basin carve by province site distance.
	var wp := _worley(x, y)
	var carve := 0.0
	var pname: String = wp["p"]
	var dmin: float = wp["d"]
	if pname == "impact_crater":
		carve = -relief * 0.12 * exp(-pow(dmin / (lt * 0.7), 2.0))
	elif pname == "sediment_basin" or pname == "evaporite_flat":
		carve = -relief * 0.10 * exp(-pow(dmin / (lt * 1.1), 2.0))
	return elev + carve

func _slope(x: float, y: float) -> float:
	var hx := 12.0
	var dx := (_elevation(x + hx, y) - _elevation(x - hx, y)) / (2.0 * hx)
	var dy := (_elevation(x, y + hx) - _elevation(x, y - hx)) / (2.0 * hx)
	return clampf(sqrt(dx * dx + dy * dy) / 100.0, 0.0, 1.0)

## Deterministic hash-grid Worley: nearest two province sites + blend.
func _worley(x: float, y: float) -> Dictionary:
	var cell := 9000.0
	var cx := floori(x / cell)
	var cy := floori(y / cell)
	var best := 1e18
	var second := 1e18
	var bp := ""
	var sp2 := ""
	var bx := 0.0
	var by := 0.0
	for io in 3:
		for jo in 3:
			var gx := cx + io - 1
			var gy := cy + jo - 1
			var idc := _site_id(gx, gy)
			var sxp := (float(gx) + _rand_cell(gx, gy, 0)) * cell
			var syp := (float(gy) + _rand_cell(gx, gy, 1)) * cell
			var ddx := x - sxp
			var ddy := y - syp
			var dist := ddx * ddx + ddy * ddy
			if dist < best:
				second = best
				sp2 = bp
				best = dist
				bp = _province_from_id(idc)
				bx = sxp
				by = syp
			elif dist < second:
				second = dist
				sp2 = _province_from_id(idc)
	var blend := clampf((best) / maxf(best + second, 1e-9), 0.0, 1.0)
	return {
		"p": bp, "s": sp2, "blend": blend, "d": sqrt(best),
		"sx": bx, "sy": by,
	}

func _site_id(gx: int, gy: int = 0) -> int:
	var n := (gx * 73856093) ^ (gy * 19349663) ^ (world_seed * 0x45D9F3B)
	n = (n * 0x9E3779B1) & 0x7FFFFFFF
	n = (n ^ (n >> 15)) & 0x7FFFFFFF
	return n

func _rand_cell(gx: int, gy: int, k: int) -> float:
	var h := _site_id(gx * 31 + gy * 17 + k)
	return (float(h % 1000) / 1000.0 - 0.5) * 0.8 + 0.5

func _province_from_id(idc: int) -> String:
	var total := 0.0
	for k in PROVINCE_KEYS:
		total += _province_weights[k]
	var r := (idc % 100000) / 100000.0 * total
	var acc := 0.0
	for k in PROVINCE_KEYS:
		acc += _province_weights[k]
		if r <= acc:
			return k
	return "craton_highlands"