# thermal_state.gd
# -----------------------------------------------------------------------------
# Per-cell thermal solution: resolved surface temperature plus the components
# of the energy balance so that the number can be audited.
# -----------------------------------------------------------------------------
class_name ThermalState
extends RefCounted

var temperature := 200.0              # K surface
var substrate_temperature := 200.0    # K deep substrate
var atmosphere_temperature := 288.15  # K reference air temperature (column)
var day_factor := 1.0
var flux_factor := 1.0

var absorbed_solar := 0.0             # W m^-2
var downwelling_ir := 0.0             # W m^-2 (from atmosphere)
var geothermal := 0.0                 # W m^-2
var out_ir := 0.0                     # W m^-2
var sensible := 0.0                   # W m^-2
var latent := 0.0                     # W m^-2
var net := 0.0                        # residual

var convergence := ""
var iterations := 0

func residual() -> float:
	return absorbed_solar + downwelling_ir + geothermal - out_ir - sensible - latent

func energies() -> Dictionary:
	return {
		"solar": absorbed_solar, "down_ir": downwelling_ir, "geothermal": geothermal,
		"out_ir": out_ir, "sensible": sensible, "latent": latent, "net": residual(),
	}