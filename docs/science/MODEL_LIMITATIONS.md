# Model Limitations

This file is intentionally conservative. A green test suite means the implementation is numerically coherent; it does not mean Star Hollow is a full planetary climate/geochemistry code.

## Calculated now
- gravity from mass/radius;
- orbital stellar flux from luminosity/orbit approximation;
- equilibrium-temperature reference;
- ideal-gas atmospheric density and scale height;
- hydrostatic local pressure approximation;
- Jeans-parameter atmospheric-retention diagnostic;
- partial pressures and mean molar mass;
- radiative, sensible, latent and conductive energy terms;
- pressure-aware pure-species phase classification;
- stoichiometric mineral allocation/conservation;
- deterministic geological fields;
- atmospheric versus condensed volatile mass bookkeeping;
- deterministic statistical sea/equipotential levels from condensed inventory;
- quantitative material-distance fingerprints.

## Simplified physical / empirical
- gray greenhouse optical depth;
- near-surface atmospheric thermal coupling;
- one-column lapse/hydrostatic atmosphere;
- conductivity through one effective regolith layer;
- saturation curves between anchor points;
- weathering kinetics;
- erosion/sediment transport;
- oxidation/hydration indices;
- surface-cover fraction from atmospheric condensation;
- representative-terrain volume solve for condensed reservoirs;
- Earth-like vegetation suitability;
- long-timescale atmospheric retention from a Jeans-escape heuristic.

## Heuristic
- many geological enrichment amplitudes;
- surface roughness/clast abundance;
- some material optical properties;
- tholin/organic production;
- visual color mapping.

## Not implemented yet
- 3-D atmospheric circulation and weather;
- clouds with microphysics;
- line-by-line radiative transfer;
- photochemistry;
- hydrodynamic escape, sputtering, ion pickup and detailed upper-atmosphere evolution;
- tectonic plate evolution;
- river routing, watershed/drainage networks and groundwater flow;
- dynamic precipitation/evaporation mass transport between cells;
- ocean circulation, waves and tides;
- impact chronology;
- full magma thermodynamics;
- full Gibbs minimization using temperature/pressure-dependent chemical potentials;
- activity/fugacity models for solutions;
- brine/electrolyte equilibrium;
- high-pressure H2O polymorph boundaries (Ice VI/VII/VIII/X) in the playable surface solver;
- superionic water and metallic hydrogen models;
- high-pressure equations of state;
- non-Earth-like biology.

## Scientific naming

A generated name is a human-readable description, not a unique substance identifier. Material identity comes from the numerical fingerprint.

## "Infinite" materials

The real periodic table is finite. Star Hollow's huge discovery space comes from continuous ratios, mineral/phase fractions, texture, alteration and environmental state. In a finite-precision computer the number of states is finite but astronomically large.

## No fake precision

The probe intentionally reports model fidelity and solver residual. Display precision should be tightened further as per-property uncertainty metadata is added.
