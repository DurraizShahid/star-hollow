# Star Hollow Scientific Model

Generator version: **4**. Internal scientific quantities are SI unless a field says otherwise.

Star Hollow follows one directional rule: **science state is authoritative; graphics are a derived view**.

## Cell state

Each scientific cell resolves four coupled layers:

1. **Substrate** — elemental budget, normative mineral assemblage, grain/bulk properties, regolith and alteration.
2. **Surface cover** — sediment, clasts, salts, condensed volatile frost/liquid, organics and vegetation where explicitly enabled.
3. **Local atmosphere** — composition, hydrostatic local pressure, density, scale height, humidity and wind.
4. **Thermal state** — ground, shallow substrate and near-surface air temperatures plus audited energy fluxes.

The solver iterates temperature, condensation, conserved surface-reservoir phase, albedo and near-surface air coupling, then evaluates slower weathering/sediment/biology feedback and closes the thermal loop again.

## Hydrosphere / condensed reservoirs

Volatile mass that is not retained in the atmosphere is preserved as a planet-mean condensed column. A deterministic statistical sea/equipotential level is solved against the generated elevation distribution so large liquid/ice reservoirs emerge from inventory + phase stability rather than an authored ocean mask. See `HYDROSPHERE_MODEL.md`.

## Planet mechanics

Surface gravity:

```
g = G M / R²
```

Time-averaged inverse-square stellar flux for the current eccentric-orbit approximation:

```
<S> = L / (4 π a² sqrt(1-e²))
```

Reference equilibrium temperature:

```
T_eq = [ S (1-A) / (4 ε σ) ]^(1/4)
```

This is an initialization/reference temperature, not the final surface temperature.

## Atmosphere

Before atmospheric pressure is solved, the accessible volatile inventory is attenuated by a documented Jeans-escape retention approximation based on molecular mass, gravity, radius, upper-atmosphere temperature proxy and planetary age. Reference presets may override present-day pressure/composition/mean atmospheric temperature for validation.

Mean molar mass:

```
Mbar = Σ x_i M_i
```

Ideal-gas density:

```
rho = P Mbar / (R T)
```

Isothermal scale height:

```
H = R T / (Mbar g)
```

Local hydrostatic pressure:

```
P(z) ≈ P0 exp(-z/H)
```

The current greenhouse model is gray/parameterized and therefore fidelity level 0–2 depending on the quantity. It is not line-by-line radiative transfer.

## Surface energy balance

The steady surface solve is:

```
0 = Qsolar + QIR_down + Qgeothermal
    - QIR_up - Qsensible - Qlatent - Qconductive
```

with

```
Qsolar = (1-A) S_local
QIR_up = ε σ T_surface^4
Qsensible = C_H rho c_p U (T_surface - T_air)
Qconductive ≈ k_eff (T_surface - T_deep) / d
```

Latent heat uses the resolved condensable species, its saturation pressure, atmospheric partial pressure and phase-dependent latent heat.

The temperature root is bracketed and bisected when possible. If no physical root exists inside the numerical domain, the minimum-residual state is returned and explicitly marked non-converged.

## Phase logic

A pure species is classified using triple/critical points plus approximate sublimation, vapor-pressure and melting boundaries. The solver distinguishes solid, liquid, vapor and supercritical states. Pressure is never ignored.

## Chemistry

Elemental inventory is conserved through a stoichiometric normative allocation. This is **not yet full Gibbs free-energy minimization**. The architecture records that limitation rather than describing the norm as equilibrium thermodynamics.

## Spatial fields

Noise/Voronoi/domain fields define geological boundary conditions such as elevation, province, enrichment, fracture, wind and volcanic/impact tendency. They do **not** select a visual biome. Chemistry and physics resolve the material afterward.

## Fidelity

- Level 0 — heuristic
- Level 1 — empirical approximation
- Level 2 — simplified physical model
- Level 3 — thermodynamic calculation with sufficient data
- Level 4 — reference/high-fidelity model

The probe exposes convergence and approximation flags so numerical precision is not confused with scientific certainty.
