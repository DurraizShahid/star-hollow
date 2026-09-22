# thermal_state.gd
class_name ThermalState
extends RefCounted

var temperature := 200.0               # K, exposed surface
var shallow_subsurface_temperature := 200.0 # K, ~1 m effective layer
var substrate_temperature := 200.0     # K, deeper thermal reservoir
var atmosphere_temperature := 288.15   # K, local near-surface air
var day_factor := 1.0
var flux_factor := 1.0

var absorbed_solar := 0.0              # W m^-2
var downwelling_ir := 0.0
var geothermal := 0.0
var out_ir := 0.0
var sensible := 0.0
var latent := 0.0
var conductive := 0.0
var net := 0.0
var areal_heat_capacity := 0.0         # J m^-2 K^-1 for modeled skin layer

var convergence := ""
var iterations := 0
var residual_w_m2 := INF
var converged := false

func residual() -> float:
	return absorbed_solar + downwelling_ir + geothermal - out_ir - sensible - latent - conductive

func energies() -> Dictionary:
	return {
		"solar": absorbed_solar, "down_ir": downwelling_ir, "geothermal": geothermal,
		"out_ir": out_ir, "sensible": sensible, "latent": latent,
		"conductive": conductive, "net": residual(),
	}
