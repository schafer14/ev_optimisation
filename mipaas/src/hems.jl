module HemsModel

    using JuMP
    import HTTP
    import HiGHS
    import JSON3

    export EVObject, PVObject, BESSObject, HEMSObject, solve_hems, SoCAt, CycleCost, PriceObject, EVSoCAt, EVCycleCost, EVRampPenalty

    abstract type EVConstraint end

    struct EVSoCAt <: EVConstraint
        at::Int
        soc::Float64
    end

    struct EVCycleCost <: EVConstraint
        cost_per_kwh::Float64 # $/kWh
    end

    struct EVRampPenalty <: EVConstraint
        cost::Float64 
    end

    struct DriveTime <: EVConstraint
        start_interval::Int 
        end_interval::Int 
        soc_drain::Float64
    end

    function apply!(model, i, c::DriveTime)
        for t in c.start_interval:c.end_interval
            fix(model[:ev_charge_plan][i, t], 0.0; force=true)
        end
    end

    function apply!(model, i, c::EVSoCAt)
      @constraint(model, model[:ev_soc][i, c.at] >= c.soc)
    end

    function apply!(model, i, c::EVCycleCost)
      add_to_expression!(model[:ev_cycle_penalty][i], c.cost_per_kwh * model[:ev_throughputs][i])
    end

    function apply!(model, i, c::EVRampPenalty)
      charge = model[:ev_charge_plan]
      T = size(charge, 2)
      ramp = @variable(model, [t=1:T-1], lower_bound=0, base_name="ev_ramp_$i")
      @constraint(model, [t=1:T-1], ramp[t] >= charge[i, t+1] - charge[i, t])
      @constraint(model, [t=1:T-1], ramp[t] >= charge[i, t] - charge[i, t+1])
      add_to_expression!(model[:ev_ramp_penalty][i], c.cost * sum(ramp))
    end

    JSON3.StructType(::Type{<:EVConstraint}) = JSON3.AbstractType()
    JSON3.subtypekey(::Type{EVConstraint}) = :type
    JSON3.subtypes(::Type{EVConstraint}) = (SoCAt=EVSoCAt, CycleCost=EVCycleCost, RampPenalty=EVRampPenalty, DriveTime=DriveTime)
    JSON3.StructType(::Type{EVSoCAt}) = JSON3.Struct()
    JSON3.StructType(::Type{EVCycleCost}) = JSON3.Struct()
    JSON3.StructType(::Type{EVRampPenalty}) = JSON3.Struct()
    JSON3.StructType(::Type{DriveTime}) = JSON3.Struct()

    Base.@kwdef struct EVObject
        capacity_kwh::Float64
        max_charge_kw::Float64
        soc::Float64                       # SoC at t=0

        min_soc::Float64 = 0.1
        max_soc::Float64 = 1.0

        constraints::Vector{EVConstraint} = EVConstraint[]
    end

    struct PVObject
        capacity_kw::Float64        # nameplate capacity
    end

    abstract type BESSConstraint end

    struct SoCAt <: BESSConstraint
        at::Int
        soc::Float64
    end

    struct CycleCost <: BESSConstraint
        cost_per_kwh::Float64 # $/kWh
    end

    JSON3.StructType(::Type{<:BESSConstraint}) = JSON3.AbstractType()
    JSON3.subtypekey(::Type{BESSConstraint}) = :type
    JSON3.subtypes(::Type{BESSConstraint}) = (SoCAt=SoCAt, CycleCost=CycleCost)
    JSON3.StructType(::Type{SoCAt}) = JSON3.Struct()
    JSON3.StructType(::Type{CycleCost}) = JSON3.Struct()

    function apply!(model, i, c::SoCAt)
      @constraint(model, model[:bess_soc][i, c.at] >= c.soc)
    end

    function apply!(model, i, c::CycleCost)
      add_to_expression!(model[:bess_cycle_penalty][i], c.cost_per_kwh * model[:bess_throughputs][i])
    end

    Base.@kwdef struct BESSObject
        capacity_kwh::Float64       # usable energy capacity
        max_charge_kw::Float64      # max charge power
        max_discharge_kw::Float64   # max discharge power
        efficiency::Float64 = 1     # round-trip efficiency (0-1)
        soc::Float64                # SoC at t=0 (0-1)

        min_soc::Float64 = 0
        max_soc::Float64 = 1

        unused_energy_value::Float64 = 0

        constraints::Vector{BESSConstraint} = BESSConstraint[]
    end

    Base.@kwdef struct PriceObject
        import_price::Vector{Float64}   # $/kWh per timestep
        export_price::Vector{Float64}   # $/kWh per timestep
    end

    struct HEMSObject
        evs::Vector{EVObject}
        pv::Union{PVObject, Nothing}
        bess::Vector{BESSObject}

        prices::PriceObject
        solar::Vector{Float64}
        load::Vector{Float64}
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

        @variable(model, 0 <= ev_soc[e=1:n_evs, 1:288] <= 1)
        @variable(model, 0 <= bess_soc[b=1:n_bess, 1:288] <= 1)

        @variable(model, grid_import[1:288] >= 0)
        @variable(model, grid_export[1:288] >= 0)

        @expression(model, bess_plan[b=1:n_bess, t=1:288], bess_charge[b, t] - bess_discharge[b, t])
        @expression(model, bess_throughputs[b=1:n_bess], sum(bess_charge[b, t] + bess_discharge[b, t] for t in 1:288) * dt)

        @expression(model, bess_cycle_penalty[b=1:n_bess], AffExpr(0.0))
        @expression(model, ev_cycle_penalty[e=1:n_evs], AffExpr(0.0))
        @expression(model, ev_throughputs[e=1:n_evs], sum(ev_charge_plan[e, t] for t in 1:288) * dt)

        @expression(model, ev_ramp_penalty[1:n_evs], AffExpr(0.0))

        for i in 1:n_bess 
          set_lower_bound.(bess_soc[i, :], data.bess[i].min_soc)
          set_upper_bound.(bess_soc[i, :], data.bess[i].max_soc)
          for c in data.bess[i].constraints
            apply!(model, i, c)
          end
        end

        for i in 1:n_evs
          set_lower_bound.(ev_soc[i, :], data.evs[i].min_soc)
          set_upper_bound.(ev_soc[i, :], data.evs[i].max_soc)
          for c in data.evs[i].constraints
            apply!(model, i, c)
          end
        end

        @constraint(model, [t=1:288],
          grid_export[t] - grid_import[t] == 
          (data.pv.capacity_kw * data.solar[t] - data.load[t] - sum(ev_charge_plan[e, t] for e in 1:n_evs) - sum(bess_plan[b, t] for b in 1:n_bess)) * dt
        )

        @expression(model, net_grid_value[t=1:288],
          data.prices.export_price[t] * grid_export[t] - data.prices.import_price[t] * grid_import[t]
        )

        # The SoC is dependant on the single SoC before it (instead of all other SoCs before it)
        # Before the SoC constraints, build a drain matrix
        ev_drain = zeros(n_evs, 288)
        for i in 1:n_evs
            for c in data.evs[i].constraints
                if c isa DriveTime
                    n = c.end_interval - c.start_interval + 1
                    for t in c.start_interval:c.end_interval
                        ev_drain[i, t] = c.soc_drain / n
                    end
                end
            end
        end

        # Modified SoC recurrence
        @constraint(model, [e=1:n_evs], 
            ev_soc[e, 1] == data.evs[e].soc + ev_charge_plan[e, 1] * dt / data.evs[e].capacity_kwh - ev_drain[e, 1])
        @constraint(model, [e=1:n_evs, t=2:288], 
            ev_soc[e, t] == ev_soc[e, t-1] + ev_charge_plan[e, t] * dt / data.evs[e].capacity_kwh - ev_drain[e, t])

        # The SoC is dependant on the single SoC before it (instead of all other SoCs before it)
        @constraint(model, [b=1:n_bess], bess_soc[b, 1] == data.bess[b].soc + bess_plan[b, 1] * data.bess[b].efficiency * dt / data.bess[b].capacity_kwh)
        @constraint(model, [b=1:n_bess, t=2:288], bess_soc[b, t] == bess_soc[b, t-1] + bess_plan[b, t] * data.bess[b].efficiency * dt / data.bess[b].capacity_kwh)

        @expression(model, bess_unused_energy_value[b=1:n_bess],
            data.bess[b].unused_energy_value * bess_soc[b, 288] * data.bess[b].capacity_kwh
        )

        @objective(model, Max,
            sum(net_grid_value)
            - sum(bess_cycle_penalty)
            - sum(ev_cycle_penalty)
            - sum(ev_ramp_penalty)
            + sum(bess_unused_energy_value)
        )

        optimize!(model)

        if termination_status(model) != MOI.OPTIMAL
          return Dict{String,Any}(
            "status" => "infeasible",
            "terminaton_status" => string(termination_status(model)),
          )
        end

        return Dict{String,Any}(
            "status" => "okay",
            "terminaton_status" => termination_status(model),
            "primal_status" => primal_status(model),
            "data" => Dict{String,Any}(
                "ev_plans" => [value.(ev_charge_plan[e, :]) for e in 1:n_evs],
                "bess_plans" => [value.(bess_plan[b, :]) for b in 1:n_bess],
                "bess_soc" => [value.(bess_soc[b, :]) for b in 1:n_bess],
                "ev_soc" => [value.(ev_soc[e, :]) for e in 1:n_evs],
                "ev_unavailable" => [
                    [(start_interval=c.start_interval, end_interval=c.end_interval)
                    for c in data.evs[e].constraints if c isa DriveTime]
                    for e in 1:n_evs
                ],
                "bess_cycle_penalty" => value.(bess_cycle_penalty),
                "ev_cycle_penalty" => value.(ev_cycle_penalty),
                "ev_ramp_penalty" => value.(ev_ramp_penalty),
                "grid_price" => sum(value.(net_grid_value)),
            )
        )

    end
end

