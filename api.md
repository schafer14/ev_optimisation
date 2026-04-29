# Optimisation Engine API

## `POST /v1-alpha/plan`

Runs the optimisation solver for a home energy management scenario. Returns 5-minute interval dispatch schedules for all devices over a 24-hour period.

All time-series arrays use **5-minute intervals** — 288 values per day (`i = (hour * 60 + minute) / 5`).

---

### Request Body

```json
{
  "solar": [0.0, 0.0, 0.12, ...],
  "load": [0.4, 0.3, 0.5, ...],
  "prices": {
    "import_price": [0.25, 0.25, 0.35, ...],
    "export_price": [0.10, 0.10, 0.10, ...]
  },
  "pv": {
    "capacity_kw": 6.6
  },
  "bess": [
    {
      "capacity_kwh": 10.0,
      "max_charge_kw": 5.0,
      "max_discharge_kw": 5.0,
      "efficiency": 0.95,
      "soc": 0.5,
      "min_soc": 0.1,
      "max_soc": 1.0,
      "unused_energy_value": 0.10,
      "constraints": [
        { "type": "CycleCost", "cost_per_kwh": 0.05 }
      ]
    }
  ],
  "evs": [
    {
      "capacity_kwh": 60.0,
      "max_charge_kw": 7.2,
      "soc": 0.5,
      "min_soc": 0.2,
      "max_soc": 1.0,
      "constraints": [
        { "type": "SoCAt", "at": 288, "soc": 0.8 },
        { "type": "DriveTime", "start_interval": 84, "end_interval": 216, "soc_drain": 0.15 },
        { "type": "CycleCost", "cost_per_kwh": 0.08 },
        { "type": "RampPenalty", "cost": 0.01 }
      ]
    }
  ]
}
```

#### Fields

| Field | Type | Description |
|-------|------|-------------|
| `solar` | `number[288]` | Solar generation profile, kW per interval |
| `load` | `number[288]` | Household load profile, kW per interval |
| `prices.import_price` | `number[288]` | Grid import price, $/kWh per interval |
| `prices.export_price` | `number[288]` | Grid export price, $/kWh per interval |
| `pv.capacity_kw` | `number` | Peak PV capacity in kW |
| `bess` | `BESS[]` | Array of battery storage units (may be empty) |
| `evs` | `EV[]` | Array of electric vehicles (may be empty) |

#### BESS Object

| Field | Type | Description |
|-------|------|-------------|
| `capacity_kwh` | `number` | Total usable capacity, kWh |
| `max_charge_kw` | `number` | Max charge power, kW |
| `max_discharge_kw` | `number` | Max discharge power, kW |
| `efficiency` | `number` | Round-trip efficiency, 0–1 |
| `soc` | `number` | Initial state of charge, 0–1 |
| `min_soc` | `number` | Minimum allowed SoC, 0–1 |
| `max_soc` | `number` | Maximum allowed SoC, 0–1 |
| `unused_energy_value` | `number` | Value of energy left in battery at end of day, $/kWh |
| `constraints` | `Constraint[]` | See constraint types below |

#### EV Object

| Field | Type | Description |
|-------|------|-------------|
| `capacity_kwh` | `number` | Battery capacity, kWh |
| `max_charge_kw` | `number` | Max charge power, kW |
| `soc` | `number` | Initial state of charge, 0–1 |
| `min_soc` | `number` | Minimum allowed SoC, 0–1 |
| `max_soc` | `number` | Maximum allowed SoC, 0–1 |
| `constraints` | `Constraint[]` | See constraint types below |

#### Constraint Types

| `type` | Fields | Description |
|--------|--------|-------------|
| `CycleCost` | `cost_per_kwh: number` | Degradation cost per kWh cycled, $/kWh |
| `SoCAt` | `at: number`, `soc: number` | Require a specific SoC at interval `at` (e.g. end-of-day target) |
| `DriveTime` | `start_interval`, `end_interval`, `soc_drain: number` | Vehicle unavailable for charging between these intervals; SoC decreases by `soc_drain` |
| `RampPenalty` | `cost: number` | Penalty coefficient for rapid changes in charge power |

---

### Response Body

```json
{
  "termination_status": "OPTIMAL",
  "data": {
    "grid_price": -4.32,
    "bess_soc": [[0.5, 0.51, ...]],
    "bess_plans": [[0.0, 2.5, ...]],
    "ev_soc": [[0.5, 0.51, ...]],
    "ev_plans": [[0.0, 7.2, ...]],
    "ev_unavailable": [
      [{ "start_interval": 84, "end_interval": 216 }]
    ]
  }
}
```

| Field | Type | Description |
|-------|------|-------------|
| `termination_status` | `string` | Solver outcome — see values below |
| `data.grid_price` | `number` | Net grid cost over the day in $; negative = net export revenue |
| `data.bess_soc` | `number[][]` | SoC trajectory per BESS unit, 288 values each (0–1) |
| `data.bess_plans` | `number[][]` | Charge/discharge schedule per BESS unit, kW per interval (positive = charge) |
| `data.ev_soc` | `number[][]` | SoC trajectory per EV, 288 values each (0–1) |
| `data.ev_plans` | `number[][]` | Charge schedule per EV, kW per interval |
| `data.ev_unavailable` | `{start_interval, end_interval}[][]` | Drive windows per EV where charging is not possible |

#### `termination_status` Values

| Value | Meaning |
|-------|---------|
| `OPTIMAL` | Solver found an optimal solution — `data` is populated |
| `INFEASIBLE` | No feasible solution exists given the constraints |
| `UNBOUNDED` | Problem is unbounded (misconfigured input) |
| `ERROR` | Internal solver error |

---

### Error Responses

| Status | Meaning |
|--------|---------|
| `429 Too Many Requests` | Rate limit exceeded; back off and retry |
| `4xx / 5xx` | Bad request or server error |
