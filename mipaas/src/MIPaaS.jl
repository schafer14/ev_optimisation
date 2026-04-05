module MIPaaS

    import HTTP
    import JSON3
    import JSON

    include("hems.jl")

    function wrap_endpoint(endpoint::Function)
        function serve_request(request::HTTP.Request)::HTTP.Response
            task = Threads.@spawn try
                ret = request.body |> String |> body -> JSON3.read(body, HemsModel.HEMSObject) |> endpoint |> JSON.json
                HTTP.Response(200, ret)
            catch err
                HTTP.Response(500, "internal error: $err")
            end
            return fetch(task)
        end
    end

    function julia_main()::Cint
        try
            port = parse(Int, get(ENV, "PORT", "8080"))
            router = HTTP.Router()
            HTTP.register!(router, "/v1-alpha/plan", wrap_endpoint(HemsModel.solve_hems))
            server = HTTP.serve!(router, HTTP.ip"0.0.0.0", port)
            @info "Solver listening" port=port
            wait(server)
        catch e
            @error "Server error" exception=e
            return 1
        end
        return 0
    end

end
