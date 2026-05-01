import HTTP
import JSON3
using MIPaaS

const CORS_HEADERS = [
    "Access-Control-Allow-Origin" => "*",
    "Access-Control-Allow-Methods" => "POST, GET, OPTIONS",
    "Access-Control-Allow-Headers" => "Content-Type",
]

# Handle preflight OPTIONS request
function handle_cors(req)
    if req.method == "OPTIONS"
        return HTTP.Response(200, CORS_HEADERS)
    end
    return nothing
end

function wrap_endpoint(endpoint::Function)
    function serve_request(request::HTTP.Request)::HTTP.Response
        cors = handle_cors(request)
        cors !== nothing && return cors


        task = Threads.@spawn try
            ret = request.body |> String |> body -> JSON3.read(body, HemsModel.HEMSObject) |> endpoint |> JSON3.write
            HTTP.Response(200, CORS_HEADERS, ret)
        catch err
            println(err)
            HTTP.Response(500, CORS_HEADERS, "internal error: $err")
        end
        return fetch(task)
    end
end

port = parse(Int, get(ENV, "PORT", "8080"))
router = HTTP.Router()
HTTP.register!(router, "/v1-alpha/plan", wrap_endpoint(solve_hems))
server = HTTP.serve!(router, HTTP.ip"0.0.0.0", port)
@info "Solver listening" port=port
wait(server)
