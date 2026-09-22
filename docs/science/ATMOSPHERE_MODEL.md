# Atmosphere Model

## Global reservoir

Random worlds derive a first-order atmospheric inventory from volatile mass, degassing fraction, planetary area and gravity. Condensable species are cold-trap capped using saturation-pressure approximations.

Validation presets can instead provide a known pressure/composition anchor so Earth/Mars/Titan/Pluto tests do not depend on arbitrary volatile inventory tuning.

## Local atmosphere

Every cell receives a local state rather than reusing one global pressure:

```
P(z) = P0 exp(-z/H)
H = RT/(Mbar g)
rho = P Mbar/(RT)
```

A dry-adiabatic lapse estimate initializes local air temperature. The near-surface air is then iteratively relaxed toward the solved ground temperature as a function of pressure and wind. This coupling is heuristic but directionally physical.

## Composition

Current nominal gases:
H2, He, N2, O2, CO2, CO, H2O, CH4, NH3, SO2 and Ar.

The database is data-driven; adding a species should not require modifying terrain rendering.

## Greenhouse

Current infrared optical depth is a gray parameterization built from partial pressures. It is not spectroscopy or a correlated-k model. The probe marks it as an approximation.

## Missing physics
- clouds;
- convection beyond the local lapse approximation;
- horizontal advection/global circulation;
- atmospheric escape;
- photochemistry and haze microphysics;
- pressure broadening/spectral radiative transfer.
