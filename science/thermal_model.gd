# thermal_model.gd
# -----------------------------------------------------------------------------
# Surface energy-balance solver.
#
# For one cell:
#   absorbed_solar = S_eff * (1 - albedo)          (S_eff = stellar * flux_factor)
#   downwelling_ir = eps_atm * sigma * T_atm^4     (eps_atm = 1 - exp(-tau))
#   geothermal     = constant (W m^-2)
#   out_ir         = eps_s * sigma * T_surf^4
#   sensible       = rho c_p C_h U (T_surf - T_atm)
#   latent         = rho C_e U (q_sat_local - q_atm) L(T)   (active on wet surfaces)
#
# Balance: 0 = absorbed + down + geo - out_ir - sensible - latent
#
# The residual generally rises steeply with T (out_ir ~ T^4), so a grid scan +
# bisection finds the stable crossing; if no sign change (extreme instellation),
# we take the minimum-residual point. Surface albedo is phase-dependent
# (ice/bare/melted), which couples the phase solver back into the balance; a few
# Picard iterations converge the temperature-albedo pair.
#
# Simplifications are documented: single-layer gray atmosphere, bulk transfer
# coefficients fixed, no diurnal averaging (static illumination field).
# -----------------------------------------------------------------------------
class_name ThermalModel
extends RefCounted

const SIGMA := SciConstants.SIGMA
const C_H := 0.0013        # bulk sensible heat transfer coefficient (heuristic)
const C_E := 0.0013        # bulk latent heat transfer coefficient (heuristic)
const MAX_ALBEDO_ITER := 6

## Solve the surface temperature for one cell.
## Returns a ThermalState with the audited energy components.
static func solve(planet: PlanetParameters, atm: AtmosphereState, ctx: Dictionary) -> ThermalState:
	var st := ThermalState.new()
	st.flux_factor = ctx.get("flux_factor", 1.0)
	st.day_factor = ctx.get("day_factor", 1.0)

	var s_eff: float = planet.stellar_flux * st.flux_factor
	st.geothermal = planet.geothermal_flux
	st.atmosphere_temperature = ctx.get("t_atm", atm.temperature)
	st.substrate_temperature = _deep_substrate(planet, ctx)

	var wind: float = ctx.get("wind_speed", 1.0)
	var density: float = atm.density
	var tau := AtmosphereModel.greenhouse_depth(atm)
	var eps_atm := 1.0 - exp(-tau)
	var t_atm := st.atmosphere_temperature

	var surf: SurfaceState = ctx.get("surface")

	# Grid scan phase to bracket the crossing.
	var lo := SciConstants.MIN_TEMPERATURE_K + 1.0
	var hi := minf(SciConstants.MAX_TEMPERATURE_K, _instellation_upper_bound(planet, s_eff))
	var t_best := 0.5 * (lo + hi)
	var best_res := 1e308

	# Picard: iterate albedo (phase-dependent).
	var albedo := surf.albedo
	for iter in range(MAX_ALBEDO_ITER):
		var lo_i := lo
		var hi_i := hi
		var crossing_lo := _net(lo_i, s_eff, albedo, eps_atm, t_atm, density, wind, surf, st.geothermal)
		var crossing_hi := _net(hi_i, s_eff, albedo, eps_atm, t_atm, density, wind, surf, st.geothermal)
		var found := crossing_lo >= 0.0 and crossing_hi <= 0.0
		if not found:
			# Find minimum |net| over a coarse grid.
			var grid_t := lo
			while grid_t <= hi:
				var r := _net(grid_t, s_eff, albedo, eps_atm, t_atm, density, wind, surf, st.geothermal)
				if absf(r) < best_res:
					best_res = absf(r)
					t_best = grid_t
					found = true
				grid_t += 5.0
		if not found:
			break
		# Bisection on the bracketed crossing.
		for _i in range(60):
			var mid := 0.5 * (lo_i + hi_i)
			var r_mid := _net(mid, s_eff, albedo, eps_atm, t_atm, density, wind, surf, st.geothermal)
			if r_mid > 0.0:
				lo_i = mid
			else:
				hi_i = mid
		t_best = 0.5 * (lo_i + hi_i)
		st.convergence = "bisection"
		st.iterations = iter + 1
		# Update phase-dependent albedo for next Picard pass.
		var new_albedo := _phase_albedo(t_best, surf)
		if absf(new_albedo - albedo) < 0.01:
			albedo = new_albedo
			break
		albedo = new_albedo

	st.temperature = SciConstants.safe_clamp(t_best, SciConstants.MIN_TEMPERATURE_K, SciConstants.MAX_TEMPERATURE_K)
	st.absorbed_solar = s_eff * (1.0 - albedo)
	st.downwelling_ir = eps_atm * SIGMA * pow(t_atm, 4.0)
	st.out_ir = surf.emissivity * SIGMA * pow(st.temperature, 4.0)
	st.sensible = _flux_sensible(density, wind, st.temperature, t_atm)
	st.latent = _flux_latent(density, wind, st.temperature, t_atm, surf, atm)
	st.net = st.residual()
	return st

static func _instellation_upper_bound(planet: PlanetParameters, s_eff: float) -> float:
	# Rough radiative-equilibrium ceiling: sigma T^4 ~ s_eff + floor.
	return pow((s_eff + 1000.0) / SIGMA, 0.25)

static func _net(t: float, s_eff: float, albedo: float, eps_atm: float, t_atm: float,
		density: float, wind: float, surf: SurfaceState, geo: float) -> float:
	var absorbed := s_eff * (1.0 - albedo)
	var down := eps_atm * SIGMA * pow(t_atm, 4.0)
	var up := surf.emissivity * SIGMA * pow(t, 4.0)
	var sens := _flux_sensible(density, wind, t, t_atm)
	var lat := _flux_latent(density, wind, t, t_atm, surf, null)
	return absorbed + down + geo - up - sens - lat

static func _flux_sensible(density: float, wind: float, t_surf: float, t_atm: float) -> float:
	return C_H * density * 1004.0 * wind * (t_surf - t_atm)

static func _flux_latent(density: float, wind: float, t_surf: float, t_atm: float, surf: SurfaceState, atm: AtmosphereState) -> float:
	# Only meaningful when the surface is wet and the atmosphere is thin of vapour.
	if surf.liquid_cover < 0.05 and surf.frost_cover < 0.05:
		return 0.0
	var v := surf.liquid_species if surf.liquid_cover > surf.frost_cover else surf.frost_species
	if v == "":
		return 0.0
	# Driving potential: saturated vapour pressure at surface vs the vapour
	# actually in the atmosphere (estimate from partial pressure if known).
	var p_sat := PhaseSolver.saturation_liquid(v, t_surf) if t_surf >= SpeciesDatabase.triple_temperature(v) else PhaseSolver.saturation_over_solid(v, t_surf)
	var p_atm := 0.0
	if atm != null and atm.species.has(v):
		p_atm = atm.partial_pressure(v)
	var q_sat := p_sat * SpeciesDatabase.molar_mass(v) / (SciConstants.R_u * maxf(t_surf, 1.0))
	var q_atm := p_atm * SpeciesDatabase.molar_mass(v) / (SciConstants.R_u * maxf(t_atm, 1.0))
	var deficit := minf(q_sat, 1.0) - minf(q_atm, 1.0)
	if deficit <= 0.0:
		return 0.0
	var phase := "liquid_to_vapor" if t_surf >= SpeciesDatabase.triple_temperature(v) else "solid_to_vapor"
	var l := Thermodynamics.latent_heat(v, phase, t_surf)
	return C_E * density * wind * deficit * l

static func _phase_albedo(t: float, surf: SurfaceState) -> float:
	# Phase-dependent albedo: fresh bright ices brighter; meltwater darker.
	var a := surf.albedo
	var ice_ok := surf.frost_cover > 0.05 and surf.frost_species != ""
	if surf.liquid_cover > 0.05:
		var liq := surf.liquid_species
		if SpeciesDatabase.is_condensable(liq):
			var m := SpeciesDatabase.get_species(liq)
			var triple: float = m["t_triple"]
			# Liquid absorbs: water-like dark (~0.06), methane lake darker.
			a = 0.06 + 0.05 * clampf((t - triple) / maxf(40.0, triple * 0.05), 0.0, 1.0)
		elif ice_ok:
			a = 0.5
	if ice_ok and t < SpeciesDatabase.triple_temperature(surf.frost_species):
		a = maxf(a, 0.7)   # cold fresh frost
	return clampf(a, 0.03, 0.92)

static func _deep_substrate(planet: PlanetParameters, ctx: Dictionary) -> float:
	# Crude geothermal-fluence floor far below diurnal skin depth.
	var top: float = ctx.get("t_atm", 285.0)
	return top + clampf(planet.geothermal_flux * 0.5, 0.0, 60.0)