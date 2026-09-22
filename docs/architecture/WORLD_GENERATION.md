# World Generation Architecture

## Authority boundaries

```
Scientific truth
    ↓
World/chunk representation
    ↓
Procedural visual representation
```

Rendering never writes scientific state.

## Chunk model

- scientific cell: 8 × 8 world meters;
- chunk: 16 × 16 scientific cells;
- chunk edge: 128 world meters;
- deterministic from generator version + planet seed + absolute coordinate;
- nearby chunks are cached;
- distant science chunks and render nodes are unloaded.

The current implementation generates chunks synchronously. Worker-thread generation is a future performance step and must only move pure data work off-thread; scene-tree/resource mutation stays on the main thread.

## Rendering resolution

Scientific state is intentionally much lower resolution than the displayed terrain. A 64×64 runtime texture interpolates the 16×16 cell field, then deterministic small-scale texture is added. This avoids pretending that an expensive thermodynamic calculation exists per pixel.

## Surface instances

Rocks and vegetation use `MultiMeshInstance2D`, keeping scene-node count bounded while supporting deterministic procedural scatter.

## Sampling

World coordinates are mapped to the containing chunk and exact cell index. This avoids the previous bug where records were compared using chunk-local coordinates against world-space positions.

## Debug views

F1 enables science visualization; F2 cycles elevation, ground/air temperature, log pressure, albedo, Fe/C/S abundance, sediment, weathering, vegetation and coupling convergence.

## Reproducibility

`WORLD_GENERATOR_VERSION` is stored separately from the seed. Any algorithm change that modifies deterministic output must increment it.
