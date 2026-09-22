# Hydrosphere Model

Star Hollow now keeps atmospheric vapor and the planet's condensed volatile reservoir as separate mass pools.

## Reservoir accounting

For each volatile species, the planet generator provides a total volatile inventory. The atmosphere consumes the portion represented by its partial pressure. The remainder is retained as a planet-mean condensed column mass:

```
m_condensed/A = max(m_total/A - P_species/g, 0)
```

This prevents cold-trapped material from disappearing after atmospheric construction.

## Statistical sea level

A deterministic representative sample of the generated elevation field is used to solve an equipotential level for each condensed species. The level is chosen so that:

```
mean(max(sea_level - elevation, 0)) = global_equivalent_depth
```

where global equivalent depth is condensed column mass divided by condensed-phase density.

This conserves the modeled planet-mean reservoir volume over the sampled terrain distribution without authored ocean masks.

## Local phase

At each cell, a reservoir is exposed only if the species is thermodynamically stable as a solid or liquid at the local surface temperature and ambient pressure. Atmospheric supersaturation and precipitation/frost are still solved separately.

The current model does not yet route water downhill, simulate river discharge, groundwater flow, salinity, tides, waves, ocean circulation, or dynamic evaporation/precipitation mass exchange between cells. Those remain separate future systems.
