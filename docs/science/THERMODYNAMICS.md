# Thermodynamics

## Current pure-species phase model

For supported volatile species the database stores triple and critical points. Below the triple point a constant-latent-heat Clausius–Clapeyron form approximates sublimation:

```
ln(P/P_ref) = (DeltaH_sub/R) (1/T_ref - 1/T)
```

Liquid vapor pressure uses a smooth Watson-shaped interpolation anchored at triple and critical points. Melting curves currently use local linear Clapeyron slopes.

This is appropriate for broad phase-regime generation, not precision vapor-pressure metrology.

## Phase decisions

The phase solver respects:
- no ordinary liquid below a species' triple pressure;
- vapor/solid sublimation boundary below the triple point;
- melting and vaporization regions above the triple point;
- supercritical classification only above both critical temperature and pressure.

Thus CO2 is not treated as if it behaved like water.

## Latent energy

Evaporation/sublimation contributes to the surface energy balance only when an actual resolved liquid/frost cover is present. Atmospheric partial pressure reduces the vapor-pressure deficit.

## Future work
- source-specific high-accuracy equations (e.g. IAPWS for H2O);
- real-fluid equations of state;
- high-pressure ice polymorphs;
- solution/brine activities;
- multi-component phase equilibrium.
