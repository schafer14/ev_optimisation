
function fish_prompt
    printf '%sMIPaaS%s > ' (set_color "teal") (set_color --reset)
end

function help
    set_color green --bold
    echo "===================================================="
    echo "  MIPaaS - Mixed Integer Programming as a Service.  "
    echo "===================================================="
end

function init
    set -gx project_root (pwd)
    set -gx project MIPaaS

    help
end
