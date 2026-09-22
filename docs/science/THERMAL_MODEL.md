# Thermal Model

The surface temperature is an energy-balance result, not procedural noise.

## Flux balance

```
F(Ts) =
  S_local (1-A)
  + eps_atm sigma T_air^4
  + F_geo
  - eps_surface sigma Ts^4
  - F_sensible
  - F_latent
  - F_conductive
```

A bisection root solve is used when the model brackets a zero. Otherwise the minimum-residual point in the numerical domain is returned and marked as non-converged.

## Sensible transfer

```
F_sensible = C_H rho c_p U (Ts - Tair)
```

The bulk coefficient is heuristic.

## Conductive transfer

```
F_conductive ≈ k_eff (Ts - Tdeep) / d
```

Porosity reduces effective conductivity. The current model uses a single effective skin/regolith layer.

## Latent transfer

Latent loss requires a resolved volatile frost or liquid. It is driven by saturation-vapor density minus the atmospheric vapor density and uses phase-appropriate latent heat.

The same atmospheric partial pressure is used both while solving the root and while reporting the final residual; this prevents the previous inconsistency where a dry-atmosphere root could be reported with a wet-atmosphere flux.

## Coupling

Thermal output modifies phase cover and albedo; phase cover modifies the next thermal solution. Near-surface air temperature is also updated each iteration.

## Numerical status

Every `ThermalState` exposes:
- root strategy;
- iteration count;
- absolute W/m² residual;
- convergence flag;
- each component of the energy budget.
