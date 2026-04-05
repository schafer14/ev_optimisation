# EV & BESS optimisation

This project demonstrates how to isolate energy resource optimisation from a
DERMS platform. The optimisation uses the [HiGHS](https://highs.dev/https://highs.dev/)
solver to optimise an EV and BESS against a spot price. This optimisation
takes into account constraints on the resources such as BESS degradation due
to cycling and API costs to "wake up" an EV (applicable to various EV models).

The optimiser will optimise an arbitrary number of EVs, BESSs consider price
, load and solar predictions. The task of generating the predictions is left
to the client. An example request body is available in the [data folder](./data).

## Gateway

An API gateway for logging, security and usage-tracking is available in the
[gateway directory](./gateway/). This will wrap up the optimisation service
with enough management utilities to turn it into an internal or external
product.
