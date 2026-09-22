# planet_parameters.gd
# -----------------------------------------------------------------------------
# Planetary physical parameters and astrophysical derivation.
#
# Units: SI throughout (m, kg, s, W, Pa, K) unless explicitly documented.
#
# Derived quantities:
#   g  = G M / R^2
#   S  = L_star / (4 pi r^2)
#   T_eq = [ S (1-A) / (4 eps sigma) ]^(1/4)     (reference blackbody with eps=1)
#
# Random planets are sampled from physically plausible distributions; presets
# (see presets()) anchor specific validation regimes.
# -----------------------------------------------------------------------------
class_name PlanetParameters
extends RefCounted

const CompositionClasses := {
	"chondritic": {
		"name": "chondritic rocky",
		"rock_elements": {"O":46.0, "Si":10.5, "Fe":18.0, "Mg":9.5, "Al":0.9, "Ca":1.1, "Na":0.5, "K":0.05, "S":5.3, "Ni":1.1, "Ti":0.09, "P":0.1, "Cr":0.4, "Mn":0.3, "C":3.5, "N":0.08, "Cl":0.07},
		"volatility": 0.02,
		"volatile_split": {"H2O":0.52, "CO2":0.20, "N2":0.05, "CH4":0.08, "NH3":0.05, "CO":0.06, "SO2":0.02, "H2":0.015, "He":0.005},
		"degas": 0.35,
	},
	"terrestrial": {
		"name": "silicate terrestrial",
		"rock_elements": {"O":45.0, "Si":21.0, "Al":8.2, "Fe":5.2, "Ca":4.1, "Na":2.4, "K":2.1, "Mg":2.4, "S":0.05, "Ni":0.05, "Ti":0.6, "P":0.1, "Cr":0.01, "Mn":0.09, "C":0.35, "N":0.01, "Cl":0.05},
		"volatility": 0.006,
		"volatile_split": {"H2O":0.55, "CO2":0.30, "N2":0.07, "CH4":0.02, "NH3":0.005, "CO":0.01, "SO2":0.015, "H2":0.02, "He":0.01},
		"degas": 0.9,
	},
	"iron_rich": {
		"name": "iron-rich metallic",
		"rock_elements": {"Fe":60.0, "Ni":3.2, "S":3.5, "O":16.0, "Si":10.0, "Mg":3.0, "C":1.5, "Cr":0.8, "Mn":0.5, "Al":0.5, "Ca":0.5, "Na":0.1, "K":0.05, "Ti":0.25, "P":0.2},
		"volatility": 0.01,
		"volatile_split": {"H2O":0.30, "CO2":0.25, "N2":0.10, "CH4":0.10, "NH3":0.05, "CO":0.08, "SO2":0.08, "H2":0.02, "He":0.02},
		"degas": 0.4,
	},
	"carbon_rich": {
		"name": "carbonaceous",
		"rock_elements": {"C":28.0, "O":40.0, "Si":13.0, "Fe":9.0, "Mg":4.0, "Al":1.0, "Ca":1.2, "Na":0.4, "K":0.2, "S":1.5, "Ni":0.5, "Ti":0.1, "P":0.05, "N":0.5, "Cl":0.05, "Cr":0.1, "Mn":0.05},
		"volatility": 0.04,
		"volatile_split": {"H2O":0.32, "CO2":0.22, "CH4":0.16, "N2":0.09, "NH3":0.04, "CO":0.10, "SO2":0.03, "H2":0.02, "He":0.02},
		"degas": 0.55,
	},
	"ice_rich": {
		"name": "volatile-rich icy",
		"rock_elements": {"O":40.0, "Si":21.0, "Fe":5.0, "Mg":8.0, "Al":6.0, "Ca":5.0, "Na":2.0, "K":1.5, "S":3.0, "Ni":0.3, "C":4.0, "N":0.8, "Ti":0.4, "P":0.1, "Cl":0.5},
		"volatility": 0.25,
		"volatile_split": {"H2O":0.45, "CO2":0.10, "N2":0.18, "CH4":0.12, "NH3":0.06, "CO":0.06, "SO2":0.02, "H2":0.005, "He":0.0},
		"degas": 0.5,
	},
}

## Major element symbols used for inventory vectors (shared order everywhere).
const ELEMENT_ORDER := ["O", "Si", "Fe", "Mg", "Al", "Ca", "Na", "K", "C", "S", "N", "Ni", "Ti", "P", "Cr", "Mn", "Cl", "H"]

const VOLATILE_ORDER := ["H2O", "CO2", "N2", "CH4", "NH3", "CO", "SO2", "H2", "He"]

# --- fields ------------------------------------------------------------------
var seed: int = 0
var generator_version: int = SciConstants.WORLD_GENERATOR_VERSION
var name: String = ""
var preset: String = ""

# stellar
var stellar_luminosity := SciConstants.SOLAR_LUMINOSITY        # W
var stellar_effective_temperature := 5772.0                     # K
var semi_major_axis := SciConstants.AU_M                        # m
var eccentricity := 0.0
var obliquity := 23.44                                          # deg
var rotation_period := 24.0 * 3600.0                            # s

# planet bulk
var mass := SciConstants.EARTH_MASS                             # kg
var radius := SciConstants.EARTH_RADIUS                         # m
var age := 4.54e9                                               # years
var biosphere_enabled := false                                  # inhabitance is explicit; habitability is calculated separately
var atmosphere_pressure_override_pa := -1.0                     # <=0 means derive from volatile reservoir
var atmosphere_mole_fraction_override := {}                     # validation/preset atmosphere
var geothermal_flux := SciConstants.EARTH_GEOTHERMAL_FLUX       # W m^-2

# inventories (mass fractions of rock + volatiles)
var rock_elements := {}                                          # symbol -> mass fraction
var volatile_inventory := {}                                     # species -> global mass fraction
var volatility_fraction := 0.006
var degas_fraction := 0.9

# derived
var surface_gravity := SciConstants.EARTH_GRAVITY               # m s^-2
var mean_density := 5514.0                                       # kg m^-3
var stellar_flux := SciConstants.SOLAR_FLUX_EARTH               # W m^-2
var equilibrium_temperature := 255.0                            # K (eps=1 reference)
var albedo_initial := 0.30

# --- generation ----------------------------------------------------------------
static func from_random(seed_value: int, planet_name: String = "") -> PlanetParameters:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var p := PlanetParameters.new()
	p.seed = seed_value
	p.name = planet_name if planet_name != "" else "Procedural World %d" % seed_value

	# Stellar: luminosity, effective temperature (mass-luminosity-esque spread).
	var l_sun := pow(10.0, rng.randf_range(-1.3, 0.7))           # 0.05 .. 5 L_sun
	var t_eff := rng.randf_range(2800.0, 6500.0)
	p.stellar_luminosity = SciConstants.SOLAR_LUMINOSITY * l_sun
	p.stellar_effective_temperature = t_eff

	# Orbital flux: broad log range around Earth's.
	var s_over_earth := pow(10.0, rng.randf_range(-1.0, 1.4))     # 0.1 .. 25 x Earth
	p.semi_major_axis = sqrt(p.stellar_luminosity / (4.0 * PI * SciConstants.SOLAR_FLUX_EARTH * s_over_earth))
	p.eccentricity = rng.randf_range(0.0, 0.35)
	p.obliquity = rng.randf_range(0.0, 60.0)
	p.rotation_period = rng.randf_range(0.5, 50.0) * 24.0 * 3600.0

	# Mass/radius: rocky mass-radius; keep gravity sane (0.3..5.5 g).
	p.mass = SciConstants.EARTH_MASS * pow(10.0, rng.randf_range(-1.0, 1.2))
	p.radius = SciConstants.EARTH_RADIUS * pow(p.mass / SciConstants.EARTH_MASS, 0.27)
	p.mean_density = p.mass / ((4.0 / 3.0) * PI * pow(p.radius, 3.0))

	# Geothermal: decays with age; younger/iron cores hotter.
	p.age = 1.0e9 * pow(10.0, rng.randf_range(-0.6, 1.05))         # 0.25..11 Gyr
	var core_factor := 1.0 + 1.2 * (p.mass / SciConstants.EARTH_MASS)
	p.geothermal_flux = 0.09 * core_factor * pow(4.5e9 / (0.1 + p.age), 0.9)

	# Composition class.
	var class_keys: Array = CompositionClasses.keys()
	var ck: String = class_keys[rng.randi_range(0, class_keys.size() - 1)]
	_apply_composition(p, ck, 0.5)
	return p

static func from_preset(preset_name: String, seed_value: int = 1) -> PlanetParameters:
	var p := PlanetParameters.new()
	p.seed = seed_value
	p.preset = preset_name
	match preset_name:
		"airless_rocky":
			_set_basic(p, "Airless Rock", 3.828e26 * 0.08, 3400.0, 0.2 * SciConstants.AU_M, 28.0, 0.05 * SciConstants.EARTH_MASS)
			p.radius = SciConstants.EARTH_RADIUS * 0.28
			p.mean_density = p.mass / ((4.0 / 3.0) * PI * pow(p.radius, 3.0))
			p.age = 4.5e9
			p.geothermal_flux = 0.02
			_apply_composition(p, "chondritic", 0.2)
			p.degas_fraction = 0.0001
			p.albedo_initial = 0.16
		"earthlike":
			_set_basic(p, "Earth-like", SciConstants.SOLAR_LUMINOSITY, 5772.0, SciConstants.AU_M, 23.44, SciConstants.EARTH_MASS)
			p.radius = SciConstants.EARTH_RADIUS
			p.mean_density = 5514.0
			p.age = 4.54e9
			p.geothermal_flux = 0.065
			_apply_composition(p, "terrestrial", 0.55)
			p.volatility_fraction = 0.006
			p.degas_fraction = 0.9
			p.albedo_initial = 0.30
			p.biosphere_enabled = true
			p.atmosphere_pressure_override_pa = SciConstants.EARTH_PRESSURE
			p.atmosphere_mole_fraction_override = {"N2":0.7808,"O2":0.2094,"Ar":0.0093,"CO2":0.0004,"H2O":0.0001}
		"marslike":
			_set_basic(p, "Mars-like", SciConstants.SOLAR_LUMINOSITY, 5772.0, SciConstants.AU_M * 1.52, 25.19, SciConstants.EARTH_MASS * 0.107)
			p.radius = SciConstants.EARTH_RADIUS * 0.532
			p.mean_density = p.mass / ((4.0 / 3.0) * PI * pow(p.radius, 3.0))
			p.age = 4.6e9
			p.geothermal_flux = 0.02
			_apply_composition(p, "iron_rich", 0.8)
			p.volatility_fraction = 0.004
			p.degas_fraction = 0.06
			p.albedo_initial = 0.25
			p.atmosphere_pressure_override_pa = SciConstants.MARS_PRESSURE
			p.atmosphere_mole_fraction_override = {"CO2":0.9532,"N2":0.027,"Ar":0.016,"O2":0.0013,"CO":0.0008}
		"titanlike":
			_set_basic(p, "Titan-like", SciConstants.SOLAR_LUMINOSITY, 5772.0, SciConstants.AU_M * 9.54, 26.73, SciConstants.EARTH_MASS * 0.0225)
			p.radius = SciConstants.EARTH_RADIUS * 0.404
			p.mean_density = p.mass / ((4.0 / 3.0) * PI * pow(p.radius, 3.0))
			p.age = 4.5e9
			p.geothermal_flux = 0.018
			_apply_composition(p, "ice_rich", 0.5)
			p.volatility_fraction = 0.35
			p.degas_fraction = 0.9
			p.albedo_initial = 0.22
			p.atmosphere_pressure_override_pa = SciConstants.TITAN_PRESSURE
			p.atmosphere_mole_fraction_override = {"N2":0.984,"CH4":0.014,"H2":0.001,"CO":0.001}
		"plutolike":
			_set_basic(p, "Pluto-like", SciConstants.SOLAR_LUMINOSITY, 5772.0, SciConstants.AU_M * 39.5, 57.0, SciConstants.EARTH_MASS * 0.0022)
			p.radius = SciConstants.EARTH_RADIUS * 0.185
			p.mean_density = p.mass / ((4.0 / 3.0) * PI * pow(p.radius, 3.0))
			p.age = 4.6e9
			p.geothermal_flux = 0.004
			_apply_composition(p, "ice_rich", 0.6)
			p.volatility_fraction = 0.55
			p.degas_fraction = 0.55
			p.albedo_initial = 0.50
			p.atmosphere_pressure_override_pa = SciConstants.PLUTO_PRESSURE
			p.atmosphere_mole_fraction_override = {"N2":0.98,"CH4":0.015,"CO":0.005}
		"hot_lava":
			_set_basic(p, "Hot Lava", SciConstants.SOLAR_LUMINOSITY * 4.0, 6200.0, 0.4 * SciConstants.AU_M, 5.0, SciConstants.EARTH_MASS * 0.6)
			p.radius = SciConstants.EARTH_RADIUS * pow(0.6, 0.27)
			p.mean_density = p.mass / ((4.0 / 3.0) * PI * pow(p.radius, 3.0))
			p.age = 0.4e9
			p.geothermal_flux = 3.5
			_apply_composition(p, "terrestrial", 0.5)
			p.volatility_fraction = 0.002
			p.degas_fraction = 0.95
			p.albedo_initial = 0.12
		"carbon_rich":
			_set_basic(p, "Carbon-rich", SciConstants.SOLAR_LUMINOSITY * 0.5, 5200.0, 1.1 * SciConstants.AU_M, 20.0, SciConstants.EARTH_MASS * 0.35)
			p.radius = SciConstants.EARTH_RADIUS * pow(0.35, 0.27)
			p.mean_density = p.mass / ((4.0 / 3.0) * PI * pow(p.radius, 3.0))
			p.age = 4.2e9
			p.geothermal_flux = 0.04
			_apply_composition(p, "carbon_rich", 0.7)
			p.volatility_fraction = 0.02
			p.degas_fraction = 0.5
			p.albedo_initial = 0.10
		"ocean_pressure":
			_set_basic(p, "High-Pressure Ocean", SciConstants.SOLAR_LUMINOSITY * 0.6, 5600.0, 0.9 * SciConstants.AU_M, 25.0, SciConstants.EARTH_MASS * 0.8)
			p.radius = SciConstants.EARTH_RADIUS * pow(0.8, 0.27)
			p.mean_density = p.mass / ((4.0 / 3.0) * PI * pow(p.radius, 3.0))
			p.age = 4.0e9
			p.geothermal_flux = 0.09
			_apply_composition(p, "ice_rich", 0.8)
			p.volatility_fraction = 0.30
			p.degas_fraction = 1.0
			p.albedo_initial = 0.35
		_:
			push_warning("Unknown preset '%s'; falling back to random." % preset_name)
			return from_random(seed_value)
	p._finalize()
	return p

static func _set_basic(p: PlanetParameters, label: String, luminosity: float, t_eff: float,
		sma_m: float, obliquity: float, mass_kg: float) -> void:
	p.name = label
	p.stellar_luminosity = luminosity
	p.stellar_effective_temperature = t_eff
	p.semi_major_axis = sma_m
	p.obliquity = obliquity
	p.mass = mass_kg
	p.rotation_period = 24.0 * 3600.0

static func _apply_composition(p: PlanetParameters, class_key: String, mix_x: float) -> void:
	var c: Dictionary = CompositionClasses[class_key]
	p.rock_elements = c["rock_elements"].duplicate()
	p.volatility_fraction = c["volatility"]
	p.degas_fraction = c["degas"]
	p.volatile_inventory = c["volatile_split"].duplicate()
	# Minor per-planet compositional jitter if the caller passed a randomness control.
	if mix_x > 0.5:
		var rng := RandomNumberGenerator.new()
		rng.seed = p.seed + 7919
		var keys := p.rock_elements.keys()
		for k in keys:
			p.rock_elements[k] *= rng.randf_range(0.85, 1.15)
		_normalize_fractions(p.rock_elements)

static func _normalize_fractions(d: Dictionary) -> void:
	var tot := 0.0
	for k in d.keys():
		tot += d[k]
	if tot <= 0.0:
		return
	for k in d.keys():
		d[k] /= tot

func _finalize() -> void:
	# If radius/mass left at defaults, derive radius from mass for consistency.
	if radius == SciConstants.EARTH_RADIUS and mass != SciConstants.EARTH_MASS and is_zero_approx(abs(mass - SciConstants.EARTH_MASS)):
		radius = SciConstants.EARTH_RADIUS
	# Ensure element inventory normalized.
	if not rock_elements.is_empty():
		_normalize_fractions(rock_elements)
	_recompute_derived()

func _recompute_derived() -> void:
	surface_gravity = SciConstants.G * mass / (radius * radius)
	mean_density = mass / ((4.0 / 3.0) * PI * pow(radius, 3.0))
	var ecc_factor := sqrt(maxf(1.0 - eccentricity * eccentricity, 1.0e-9))
	stellar_flux = stellar_luminosity / (4.0 * PI * semi_major_axis * semi_major_axis * ecc_factor)
	equilibrium_temperature = pow(stellar_flux * (1.0 - albedo_initial) / (4.0 * 1.0 * SciConstants.SIGMA), 0.25)

## Call after fields are set to refresh derived quantities.
func refresh() -> void:
	_recompute_derived()

## Normalized element mass fractions (only symbols actually present).
func rock_element_fractions() -> Dictionary:
	return rock_elements

## Merged crustal inventory including hydrogenated volatiles allocated to rock? No:
## rock_elements stays the non-volatile rock budget; volatile inventory is separate.
func describe() -> String:
	var g_ratio := surface_gravity / SciConstants.EARTH_GRAVITY
	return "%s | seed %d | g=%.2fg | R=%.0f km | M=%.3f M_e | S=%.1f W/m2 | T_eq=%.0f K" % [
		name, seed, g_ratio, radius / 1e3, mass / SciConstants.EARTH_MASS, stellar_flux, equilibrium_temperature]

static func presets() -> Array:
	return [
		"airless_rocky", "earthlike", "marslike", "titanlike", "plutolike",
		"hot_lava", "carbon_rich", "ocean_pressure",
	]