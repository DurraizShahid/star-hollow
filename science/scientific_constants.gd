# scientific_constants.gd
# -----------------------------------------------------------------------------
# Fundamental physical constants and model-fidelity metadata for StarHollow.
#
# EVERY scientific quantity in this project is either
#   CALCULATED : derived inside the simulation from other quantities,
#   APPROX    : an empirical or simplified-formula approximation, or
#   HEURISTIC : a tunable, physically-motivated guess with no rigorous derivation.
# See docs/science/SCIENCE_SOURCES.md for full provenance.
#
# All code in res://science/ must be headless-safe (no scene-tree or rendering).
# -----------------------------------------------------------------------------
class_name SciConstants
extends RefCounted

## Fidelity levels (metadata attached to model outputs).
const FIDELITY_HEURISTIC := 0
const FIDELITY_EMPIRICAL := 1
const FIDELITY_SIMPLIFIED_PHYSICAL := 2
const FIDELITY_THERMODYNAMIC := 3
const FIDELITY_REFERENCE := 4

const FIDELITY_NAME := {
	FIDELITY_HEURISTIC: "heuristic",
	FIDELITY_EMPIRICAL: "empirical approximation",
	FIDELITY_SIMPLIFIED_PHYSICAL: "simplified physical model",
	FIDELITY_THERMODYNAMIC: "thermodynamic calculation",
	FIDELITY_REFERENCE: "high-fidelity / reference",
}

## Version of the world-generator (science + geology + rendering). Bump when a
## reproducibility-relevant algorithm changes so old saves can be flagged.
const WORLD_GENERATOR_VERSION := 3

# ---- Fundamental constants (SI) -------------------------------------------
const G := 6.67430e-11          # gravitational constant, m^3 kg^-1 s^-2   (CODATA 2018)
const SIGMA := 5.670374419e-8   # Stefan-Boltzmann, W m^-2 K^-4            (CODATA 2018)
const R_u := 8.314462618        # universal gas constant, J mol^-1 K^-1     (CODATA 2018)
const N_A := 6.02214076e23      # Avogadro constant, mol^-1                 (CODATA 2018)
const K_B := 1.380649e-23       # Boltzmann constant, J K^-1                (CODATA 2018)

# ---- Solar reference values ------------------------------------------------
const SOLAR_LUMINOSITY := 3.828e26      # W   (IAU nominal solar luminosity)
const SOLAR_FLUX_EARTH := 1361.0        # W m^-2 (TSI at 1 AU, SORCE/TIM reference)
const AU_M := 1.495978707e11            # m   (IAU nominal astronomical unit)

# ---- Earth reference values (validation anchors) ----------------------------
const EARTH_MASS := 5.9722e24           # kg
const EARTH_RADIUS := 6.371e6           # m
const EARTH_GRAVITY := 9.80665          # m s^-2 (standard gravity, g0)
const EARTH_PRESSURE := 101325.0        # Pa
const EARTH_TEMP_REF := 288.15          # K (15 C, commonly used reference)
const EARTH_GEOTHERMAL_FLUX := 0.065     # W m^-2 (updated continental+ocean average ~0.065)
const EARTH_ALBEDO := 0.30              # Bond albedo (reference; varies)
const EARTH_MOLAR_MASS_AIR := 0.0289644 # kg mol^-1

# ---- Astronomy (used for presets; literature values) -------------------------
const MARS_GRAVITY := 3.721             # m s^-2
const TITAN_GRAVITY := 1.352            # m s^-2 (surface gravity)
const PLUTO_GRAVITY := 0.62             # m s^-2
const MARS_PRESSURE := 610.0            # Pa (mean surface, ~6.1 mbar)
const TITAN_PRESSURE := 146.7e3         # Pa (surface, ~1.47 bar)
const PLUTO_PRESSURE := 1.0             # Pa (nominal surface pressure ~1 Pa)
const TITAN_TEMPERATURE := 94.0         # K (surface mean)
const PLUTO_TEMPERATURE := 44.0         # K (surface nominal)
const MARS_TEMPERATURE := 218.0         # K (surface mean)

## Scaling heuristics (HEURISTIC) ----------------------------------------------
## Heat-transfer coefficient: sensible exchange h = h_base * rho_ratio^0.8.
const SENSIBLE_H_BASE := 6.0            # W m^-2 K^-1 reference at 1 bar Earth-like (HEURISTIC)
const WIND_EROSION_BASE := 1.0          # dimensionless erosion k, unitless scale (HEURISTIC)
const MAX_SOLVER_ITERATIONS := 24       # coupled per-cell iteration budget
const CONVERGENCE_TOL_K := 0.05         # surface temperature convergence, K
const CONVERGENCE_TOL_RESIDUAL := 1e-3  # residual budget (unitless)

# ---- Numerical safety --------------------------------------------------------
const EPS := 1e-12
const MIN_TEMPERATURE_K := 0.5          # hard clamp to avoid division by zero
const MAX_TEMPERATURE_K := 20000.0
const MIN_PRESSURE_PA := 1e-4
const MAX_PRESSURE_PA := 1e12
const MAX_DENSITY := 30000.0            # kg m^-3 safety clamp

## Static helper: slope-safe clamp.
static func safe_clamp(x: float, lo: float, hi: float) -> float:
	if is_nan(x):
		return lo
	return clampf(x, lo, hi)

## Static helper: finite and within a sane planetary range.
static func is_physical_number(x: float) -> bool:
	return not is_nan(x) and is_finite(x) and x >= -1e30 and x <= 1e30

## Convert temperature in K to Celsius.
static func k_to_c(kelvin: float) -> float:
	return kelvin - 273.15

## Human-formatted temperature with an honesty-based precision note for docs.
static func format_kelvin(kelvin: float) -> String:
	return "%0.1f K" % kelvin

## Provenance table (documentation generated from this at build time).
static func provenance_report() -> String:
	var l: Array[String] = []
	l.append("## SciConstants provenance")
	l.append("- G, SIGMA, R_u, N_A, K_B : CODATA 2018 recommended values (reference-quality).")
	l.append("- SOLAR_LUMINOSITY : IAU nominal solar luminosity (3.828e26 W).")
	l.append("- SOLAR_FLUX_EARTH : SORCE/TIM TSI 1361 W m^-2.")
	l.append("- EARTH_* : geodetic/physics references (literature).")
	l.append("- SENSIBLE_H_BASE, WIND_EROSION_BASE : HEURISTIC tuning parameters.")
	l.append("- All thermodynamics data: see species/mineral databases and docs/science/SCIENCE_SOURCES.md.")
	return "\n".join(l)