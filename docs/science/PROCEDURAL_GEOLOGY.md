# Procedural Geology

Star Hollow uses procedural fields only to generate **geological causes**, never final biome labels.

## Boundary fields

The geology layer can supply spatially coherent:
- elevation and slope;
- province identity/blending;
- crustal composition family;
- local element enrichment;
- fracture density;
- volcanic/impact tendencies;
- wind forcing;
- illumination factor.

These fields are deterministic from the world seed and absolute coordinates.

## Material generation

The pipeline is:

```
geological fields
→ local elemental budget
→ stoichiometric mineral allocation
→ substrate physical properties
→ local atmosphere + thermal solve
→ phase cover
→ weathering
→ sediment
→ surface cover
→ renderer
```

There is deliberately no rule like "noise > 0.5 = red iron biome."

## Sediment

Sediment is derived from parent geological/weathering state and local transport proxies. Grain class and cover then feed visual appearance and surface thermal properties.

## Rendering

`ProceduralChunkRenderer` builds a runtime texture by continuously interpolating solved science cells and adding deterministic microtexture. It uses mineral composition/alteration/phase cover to derive appearance.

Rocks and vegetation are runtime MultiMesh instances whose densities come from the solved surface state. No terrain or rock sprite atlas is required.

## Remaining geological work
- explicit flow accumulation/drainage;
- mass-conserving sediment transport between cells;
- tectonic history;
- crater formation and ejecta transport;
- stratigraphy and vertical profiles.
