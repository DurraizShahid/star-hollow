# Scientific Data Sources and Provenance Policy

Star Hollow must never invent a physical constant merely to complete a table.

## Source families currently used

### Fundamental constants
- CODATA recommended values for G, R, k_B and related constants.
- Stefan–Boltzmann constant from CODATA.
- IAU nominal astronomical unit and solar luminosity.

### Molecular/phase data
Primary reference family:
- NIST Chemistry WebBook / NIST thermochemical and phase-change data.
- CRC Handbook of Chemistry and Physics for engineering reference values where NIST coverage is incomplete.

The current `SpeciesDatabase` stores triple points, critical points, molar masses and approximate latent/solid/liquid properties. Vapor-pressure curves are simplified correlations anchored to reference points; they are not a replacement for a dedicated equation of state.

### Minerals
Primary reference families:
- conventional mineral stoichiometry/mineralogy references;
- NIST/Barin/USGS-style thermochemical tables where standard Gibbs values are present;
- literature/engineering ranges for density, heat capacity and conductivity.

**Audit warning:** the initial mineral database was bootstrapped with source-family provenance, not a per-record bibliographic citation for every rounded physical property. Therefore those records remain approximation/reference candidates, not Level-4 data. A future data audit should attach source + edition/table/DOI to every numerical record.

### Validation-world anchors
Earth, Mars, Titan and Pluto reference atmospheres/pressures are intentionally approximate validation presets, not exact ephemeris/reanalysis snapshots. Values are intended to catch gross model errors.

## Provenance requirements for future data

Every new scientific datum should carry:
- quantity and unit;
- value/uncertainty when available;
- source title/database;
- stable identifier (DOI/table/version/URL when practical);
- temperature/pressure/applicability range;
- fidelity level;
- whether measured, fitted, derived or heuristic.

If a trustworthy value cannot be sourced, the code should either omit that behavior or mark an explicit approximation. Do not silently fabricate coefficients.
