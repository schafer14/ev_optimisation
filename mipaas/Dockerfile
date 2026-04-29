FROM julia:1.12 AS julia-src
FROM buildpack-deps:bookworm AS builder

COPY --from=julia-src /usr/local/julia /usr/local/julia
ENV PATH="/usr/local/julia/bin:$PATH"

WORKDIR /app

COPY Project.toml Manifest.toml ./
# RUN apt-get update && apt-get install -y gcc && rm -rf /var/lib/apt/lists/*
RUN julia --project=. -e 'using Pkg; Pkg.instantiate()'

COPY src/ src/

RUN julia -e 'using Pkg; Pkg.add("PackageCompiler")'
RUN julia --project=. -e 'using PackageCompiler; create_sysimage([:HTTP, :JSON3, :JuMP, :HiGHS]; sysimage_path="app_sysimage.so", precompile_execution_file="src/precompile_warmup.jl")'

FROM julia:1.12-bookworm
WORKDIR /app

COPY --from=builder /app/app_sysimage.so ./
COPY --from=builder /app/Project.toml ./
COPY --from=builder /app/Manifest.toml ./
COPY --from=builder /app/src/ src/
COPY --from=builder /root/.julia /root/.julia

EXPOSE 8080

ENV JULIA_NUM_PRECOMPILE_TASKS=1

CMD ["julia", "--sysimage=/app/app_sysimage.so", "--project=.", "-e", "import MIPaaS; MIPaaS.julia_main()"]
