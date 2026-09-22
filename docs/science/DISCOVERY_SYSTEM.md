# Discovery System

Real chemical elements are finite. Star Hollow therefore separates three catalogues:

1. **elements** — actual periodic-table constituents encountered;
2. **compounds/minerals** — recognized chemical/mineral phases;
3. **materials** — continuous mixtures and states.

## Material fingerprint

Each sample fingerprint contains:
- normalized elemental mass vector;
- mineral-fraction vector;
- phase/surface-cover vector;
- texture state: porosity, grain size, weathering, oxidation and hydration;
- environmental state: temperature and pressure.

The weighted distance is:

```
D =
  0.34 D_elements
+ 0.32 D_minerals
+ 0.14 D_phases
+ 0.12 D_texture
+ 0.08 D_environment
```

Component distances are normalized L1/log distances. If the nearest known material lies farther than the configured novelty threshold, a new `MAT-xxxxxx` signature is recorded.

Names are descriptions, not identity keys.

## Why this matters

Two samples called "ferruginous olivine regolith" may differ significantly enough to be separate discoveries. Conversely, tiny numerical noise does not create a fake new material every meter.

The discovery space is finite on a computer but effectively enormous because composition/state variables are continuous before quantization.
