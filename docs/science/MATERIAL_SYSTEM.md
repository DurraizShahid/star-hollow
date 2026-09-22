# Material System

## Representation

A cell begins with normalized elemental mass fractions. Geological provinces perturb the bulk budget continuously. `EquilibriumSolver` then performs stoichiometric normative allocation into candidate minerals, conserving element inventories within numerical tolerance.

The current allocation is deterministic and chemically constrained but is **not a Gibbs-minimum solver**.

## Substrate properties

`SubstrateState` tracks:
- mineral and elemental fractions;
- grain and bulk density;
- porosity;
- grain-size mean/spread;
- Kozeny–Carman-style permeability estimate;
- conductivity, heat capacity and diffusivity;
- hardness approximation;
- regolith depth;
- weathering, oxidation, hydration, moisture and organics.

## Surface cover

`SurfaceState` is separate from bedrock and tracks:
- sediment;
- rocks/boulders/pebbles/dust;
- salt/evaporite cover;
- condensed liquids/frosts;
- organic cover;
- vegetation where an explicit biosphere is enabled.

Surface radiative properties are then fed back into the thermal solve.

## Future thermodynamic equilibrium

The target formulation is:

```
minimize G = Σ n_j g_j(T,P,{a})
subject to A n = b
           n_j >= 0
```

A Level-3 implementation requires temperature/pressure-dependent phase chemical potentials and appropriate activities/fugacities. Standard formation energies at 298 K alone are insufficient, so Star Hollow intentionally does not claim this today.
