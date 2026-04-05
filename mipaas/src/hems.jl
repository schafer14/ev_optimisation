module HemsModel

    using JuMP
    import JSON
    import HTTP
    import HiGHS

    struct EVObject
        capacity_kwh::Float64                           # battery capacity
        max_charge_kw::Float64                          # max charge power
        soc::Float64                                    # SoC at plug-in (0-1)
    end

    struct PVObject
        capacity_kw::Float64        # nameplate capacity
    end

    struct BESSObject
        capacity_kwh::Float64       # usable energy capacity
        max_charge_kw::Float64      # max charge power
        max_discharge_kw::Float64   # max discharge power
        efficiency::Float64         # round-trip efficiency (0-1)
        soc::Float64                # SoC at t=0 (0-1)
    end

    struct HEMSObject
        evs::Vector{EVObject}
        pv::Union{PVObject, Nothing}
        bess::Vector{BESSObject}

        prices::Vector{Float64}
        solar::Vector{Float64}
        load::Vector{Float64}
    end

    struct Result
        ev_plans::Vector{Vector{Float64}}
        bess_plans::Vector{Vector{Float64}}
    end

    function solve_hems(data::HEMSObject)
        dt = 5/60  # hours per interval
	
        model = Model(HiGHS.Optimizer)
        set_silent(model)

        n_evs = length(data.evs)
        n_bess = length(data.bess)

        @variable(model, 0 <= ev_charge_plan[e=1:n_evs, 1:288] <= data.evs[e].max_charge_kw)
        @variable(model, 0 <= bess_charge[b=1:n_bess, 1:288] <= data.bess[b].max_charge_kw)
        @variable(model, 0 <= bess_discharge[b=1:n_bess, 1:288] <= data.bess[b].max_discharge_kw)

        @expression(model, bess_plan[b=1:n_bess, t=1:288], bess_charge[b, t] - bess_discharge[b, t])
        @expression(model, bess_throughput, sum(bess_charge[b, t] + bess_discharge[b, t] for b in 1:n_bess, t in 1:288) * dt)

        # Approximate Amber import/export tariffs based on the NEM price.
        network_fee = 0.10  # $/kWh approx network + fees
        import_price = data.prices ./ 1000 .+ network_fee
        export_price = data.prices ./ 1000  # raw wholesale
      
        @variable(model, grid_import[1:288] >= 0)
        @variable(model, grid_export[1:288] >= 0)
      
        @constraint(model, [t=1:288],
          grid_export[t] - grid_import[t] == 
          (data.pv.capacity_kw * data.solar[t] - data.load[t] - sum(ev_charge_plan[e, t] for e in 1:n_evs) - sum(bess_plan[b, t] for b in 1:n_bess)) * dt
        )

        @expression(model, net_grid_value[t=1:288],
          export_price[t] * grid_export[t] - import_price[t] * grid_import[t]
        )

        # The SoC is dependant on the single SoC before it (instead of all other SoCs before it)
        @variable(model, 0 <= ev_soc[e=1:n_evs, 1:288] <= 1)
        @constraint(model, [e=1:n_evs], ev_soc[e, 1] == data.evs[e].soc + ev_charge_plan[e, 1] * dt / data.evs[e].capacity_kwh)
        @constraint(model, [e=1:n_evs, t=2:288], ev_soc[e, t] == ev_soc[e, t-1] + ev_charge_plan[e, t] * dt / data.evs[e].capacity_kwh)

        # The SoC is dependant on the single SoC before it (instead of all other SoCs before it)
        @variable(model, 0 <= bess_soc[b=1:n_bess, 1:288] <= 1)
        @constraint(model, [b=1:n_bess], bess_soc[b, 1] == data.bess[b].soc + bess_plan[b, 1] * data.bess[b].efficiency * dt / data.bess[b].capacity_kwh)
        @constraint(model, [b=1:n_bess, t=2:288], bess_soc[b, t] == bess_soc[b, t-1] + bess_plan[b, t] * data.bess[b].efficiency * dt / data.bess[b].capacity_kwh)

        ev_degradation_cost = 0.12  # $/kWh, penalize EVs for cycling slightly higher than BESS — EV batteries are more expensive to replace
        @expression(model, ev_throughput, sum(ev_charge_plan[e, t] for e in 1:n_evs, t in 1:288) * dt)

        @variable(model, ev_ramp[e=1:n_evs, 1:287] >= 0)
        @constraint(model, [e=1:n_evs, t=1:287], ev_ramp[e, t] >= ev_charge_plan[e, t+1] - ev_charge_plan[e, t])
        @constraint(model, [e=1:n_evs, t=1:287], ev_ramp[e, t] >= ev_charge_plan[e, t] - ev_charge_plan[e, t+1])
      
        ramp_penalty = 0.001

        # EV ready by time: EV at 25% by noon.
        @constraint(model, [e=1:n_evs], ev_soc[e, 144] >= 0.25)

        # Keep BESS above 30% at the end of the day.
        @constraint(model, [b=1:n_bess], bess_soc[b, 288] >= 0.30)

        # Devices must have soc between 0 and 1
        @constraint(model, [e=1:n_evs, t=1:288], ev_soc[e, t] >= 0.0)
        @constraint(model, [e=1:n_evs, t=1:288], ev_soc[e, t] <= 1.0)
        @constraint(model, [b=1:n_bess, t=1:288], bess_soc[b, t] >= 0.0)
        @constraint(model, [b=1:n_bess, t=1:288], bess_soc[b, t] <= 1.0)

        degradation_cost = 0.05  # $/kWh for cycling bess
        terminal_value = 0.15  # $/kWh, roughly the average import price you'd avoid tomorrow so there's some reward for having charge at the end of the day
        @objective(model, Max,
            sum(net_grid_value)
            - degradation_cost * bess_throughput
            - ev_degradation_cost * ev_throughput
            + terminal_value * sum(bess_soc[b, 288] * data.bess[b].capacity_kwh for b in 1:n_bess)
            - ramp_penalty * sum(ev_ramp)
        )

        optimize!(model)
        assert_is_solved_and_feasible(model)
        solution_summary(model)

        return Dict{String,Any}(
            "status" => "okay",
            "terminaton_status" => termination_status(model),
            "primal_status" => primal_status(model),
            "data" => Dict{String,Any}(
                "ev_plans" => [value.(ev_charge_plan[e, :]) for e in 1:n_evs],
                "bess_plans" => [value.(bess_plan[b, :]) for b in 1:n_bess],
            )
        )

    end
end

