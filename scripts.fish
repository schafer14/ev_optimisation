function fish_prompt
    printf '%sMIPaaS%s > ' (set_color "cyan") (set_color normal)
end

function help
    set -l h (set_color purple)
    set -l c (set_color cyan)
    set -l d (set_color brblack)
    set -l r (set_color normal)
    echo ""
    echo "$h  MIPaaS - Mixed Integer Programming as a Service.$r"
    echo "  ────────────────────────────────────────────────"
    echo ""
    echo "  $c""start_pluto$r   $d— Start Pluto notebook server$r"
    echo "  $c""dev_server$r    $d— Start a MIPaaS development server$r"
    echo ""
end

function init
    set -gx project_root (pwd)
    set -gx project MIPaaS

    help
end

function start_pluto
    julia --project=notebooks notebooks/start.jl
end

function dev_server
    julia --project=server server/src/Server.jl
end
