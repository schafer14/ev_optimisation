function mipaas-deploy-solver
    argparse 'h/host=' 'm/mipaas_dir' -- $argv; or return

    set -q _flag_host; or set _flag_host calm
    set -q _flag_mipaas_dir; or set _flag_mipaas_dir /home/banner/Projects/moaas/mipaas

    echo "Deploying solver to $_flag_host..."

    scp -r $_flag_mipaas_dir $_flag_host:/tmp/mipaas-solver; or return 1

    ssh $_flag_host "
        sudo rm -rf /opt/mipaas
        sudo mv /tmp/mipaas-solver /opt/mipaas
        sudo chown -R mipaas:mipaas /opt/mipaas

        if [ ! -f /opt/mipaas/Manifest.toml ]; then
            julia --project=/opt/mipaas -e 'using Pkg; Pkg.instantiate()'
        fi

        sudo systemctl restart mipaas-solver
    "; or return 1

    echo "Solver deployed to $_flag_host"
end
