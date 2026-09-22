# thermal_model.gd
# Steady-state surface energy balance with gray-atmosphere IR, sensible/latent
# exchange and conductive coupling to a shallow substrate reservoir.
class_name ThermalModel
extends RefCounted

const SIGMA := SciConstants.SIGMA
const C_H := 0.0013
const C_E := 0.0013
const MAX_ALBEDO_ITER := 6
const ROOT_ITERS := 64
const SKIN_DEPTH_M := 1.0

static func solve(planet: PlanetParameters, atm: AtmosphereState, ctx: Dictionary) -> ThermalState:
	var st := ThermalState.new()
	st.flux_factor = float(ctx.get("flux_factor", 1.0))
	st.day_factor = float(ctx.get("day_factor", 1.0))
	var surf: SurfaceState = ctx.get("surface")
	var substrate: SubstrateState = ctx.get("substrate", null)

	var s_eff: float = planet.stellar_flux * st.flux_factor
	st.geothermal = planet.geothermal_flux
	st.atmosphere_temperature = float(ctx.get("t_atm", atm.temperature))
	st.substrate_temperature = float(ctx.get("deep_substrate_temperature", _deep_substrate(planet, ctx)))
	st.shallow_subsurface_temperature = st.substrate_temperature

	var wind := maxf(0.0, float(ctx.get("wind_speed", atm.wind_speed_m_s)))
	var density := atm.density
	var eps_atm := 1.0 - exp(-AtmosphereModel.greenhouse_depth(atm))
	var t_atm := st.atmosphere_temperature
	var albedo := surf.albedo

	if substrate != null:
		st.areal_heat_capacity = substrate.bulk_density * substrate.heat_capacity * SKIN_DEPTH_M

	var lo := maxf(SciConstants.MIN_TEMPERATURE_K + 0.1, 1.0)
	var hi := minf(SciConstants.MAX_TEMPERATURE_K, maxf(lo + 1.0, _instellation_upper_bound(s_eff, eps_atm, t_atm)))
	var t_best := 0.5 * (lo + hi)
	var best_abs := INF

	for iter in range(MAX_ALBEDO_ITER):
		var r_lo := _net(lo, s_eff, albedo, eps_atm, t_atm, density, wind, surf, atm,
			substrate, st.substrate_temperature, st.geothermal)
		var r_hi := _net(hi, s_eff, albedo, eps_atm, t_atm, density, wind, surf, atm,
			substrate, st.substrate_temperature, st.geothermal)
		var bracketed := (r_lo >= 0.0 and r_hi <= 0.0) or (r_lo <= 0.0 and r_hi >= 0.0)

		if bracketed:
			var a := lo
			var b := hi
			var ra := r_lo
			for _j in range(ROOT_ITERS):
				var mid := 0.5 * (a + b)
				var rm := _net(mid, s_eff, albedo, eps_atm, t_atm, density, wind, surf, atm,
					substrate, st.substrate_temperature, st.geothermal)
				if signf(rm) == signf(ra):
					a = mid
					ra = rm
				else:
					b = mid
			t_best = 0.5 * (a + b)
			st.convergence = "bisection"
		else:
			# Extreme regimes may not have a root inside the numerical domain.
			# Pick the minimum-energy-residual point and report non-convergence.
			best_abs = INF
			var t := lo
			while t <= hi:
				var rr := _net(t, s_eff, albedo, eps_atm, t_atm, density, wind, surf, atm,
					substrate, st.substrate_temperature, st.geothermal)
				if absf(rr) < best_abs:
					best_abs = absf(rr)
					t_best = t
				t += maxf(1.0, (hi - lo) / 300.0)
			st.convergence = "minimum_residual"

		st.iterations = iter + 1
		var new_albedo := _phase_albedo(t_best, surf)
		if absf(new_albedo - albedo) < 0.002:
			albedo = new_albedo
			break
		albedo = new_albedo

	st.temperature = SciConstants.safe_clamp(t_best, SciConstants.MIN_TEMPERATURE_K, SciConstants.MAX_TEMPERATURE_K)
	st.absorbed_solar = s_eff * (1.0 - albedo)
	st.downwelling_ir = eps_atm * SIGMA * pow(t_atm, 4.0)
	st.out_ir = surf.emissivity * SIGMA * pow(st.temperature, 4.0)
	st.sensible = _flux_sensible(density, wind, st.temperature, t_atm)
	st.latent = _flux_latent(density, wind, st.temperature, t_atm, surf, atm)
	st.conductive = _flux_conductive(st.temperature, st.substrate_temperature, substrate)
	st.net = st.residual()
	st.residual_w_m2 = absf(st.net)
	st.converged = st.residual_w_m2 < 0.5
	# One-layer conductive estimate between surface and deep reservoir.
	st.shallow_subsurface_temperature = 0.65 * st.temperature + 0.35 * st.substrate_temperature
	return st

static func _instellation_upper_bound(s_eff: float, eps_atm: float, t_atm: float) -> float:
	var incoming := maxf(1.0, s_eff + eps_atm * SIGMA * pow(t_atm, 4.0) + 1500.0)
	return minf(SciConstants.MAX_TEMPERATURE_K, pow(incoming / SIGMA, 0.25) * 1.6)

static func _net(t: float, s_eff: float, albedo: float, eps_atm: float, t_atm: float,
		density: float, wind: float, surf: SurfaceState, atm: AtmosphereState,
		substrate: SubstrateState, deep_k: float, geo: float) -> float:
	var absorbed := s_eff * (1.0 - albedo)
	var down := eps_atm * SIGMA * pow(t_atm, 4.0)
	var up := surf.emissivity * SIGMA * pow(t, 4.0)
	var sens := _flux_sensible(density, wind, t, t_atm)
	var lat := _flux_latent(density, wind, t, t_atm, surf, atm)
	var cond := _flux_conductive(t, deep_k, substrate)
	return absorbed + down + geo - up - sens - lat - cond

static func _flux_sensible(density: float, wind: float, t_surf: float, t_atm: float) -> float:
	return C_H * density * 1004.0 * wind * (t_surf - t_atm)

static func _flux_latent(density: float, wind: float, t_surf: float, t_atm: float,
		surf: SurfaceState, atm: AtmosphereState) -> float:
	if surf.liquid_cover < 0.05 and surf.frost_cover < 0.05:
		return 0.0
	var v := surf.liquid_species if surf.liquid_cover > surf.frost_cover else surf.frost_species
	if v == "" or not SpeciesDatabase.has(v):
		return 0.0
	var p_sat := PhaseSolver.saturation_liquid(v, t_surf) 		if t_surf >= SpeciesDatabase.triple_temperature(v) 		else PhaseSolver.saturation_over_solid(v, t_surf)
	var p_atm := atm.partial_pressure(v) if atm != null and atm.species.has(v) else 0.0
	var mm := SpeciesDatabase.molar_mass(v)
	var q_sat := p_sat * mm / (SciConstants.R_u * maxf(t_surf, 1.0))
	var q_atm := p_atm * mm / (SciConstants.R_u * maxf(t_atm, 1.0))
	var deficit := clampf(q_sat - q_atm, 0.0, 1.0)
	if deficit <= 0.0:
		return 0.0
	var phase := "liquid_to_vapor" if t_surf >= SpeciesDatabase.triple_temperature(v) else "solid_to_vapor"
	return C_E * density * wind * deficit * Thermodynamics.latent_heat(v, phase, t_surf)

static func _flux_conductive(t_surface: float, t_deep: float, substrate: SubstrateState) -> float:
	if substrate == null:
		return 0.0
	var effective_k := substrate.thermal_conductivity * clampf(1.0 - 0.7 * substrate.porosity, 0.1, 1.0)
	var depth := clampf(maxf(substrate.regolith_thickness, SKIN_DEPTH_M), 0.25, 5.0)
	return effective_k * (t_surface - t_deep) / depth

static func _phase_albedo(t: float, surf: SurfaceState) -> float:
	var a := surf.albedo
	if surf.liquid_cover > 0.05:
		a = lerpf(a, 0.07, clampf(surf.liquid_cover, 0.0, 1.0))
	if surf.frost_cover > 0.05 and surf.frost_species != "":
		var cold := t < SpeciesDatabase.triple_temperature(surf.frost_species)
		a = maxf(a, lerpf(0.45, 0.78, 1.0 if cold else 0.3) * surf.frost_cover)
	return clampf(a, 0.03, 0.92)

static func _deep_substrate(planet: PlanetParameters, ctx: Dictionary) -> float:
	var top := float(ctx.get("t_atm", 285.0))
	# Geothermal flux does not directly specify a temperature without crustal k
	# and depth, so this is an explicitly simplified effective reservoir.
	return top + clampf(planet.geothermal_flux * 4.0, 0.0, 120.0)
