# Engine 10 scenarios: data requirements and access options (WP9, item 4)

**Status: investigation only. No access was granted or changed.** The Founder's clarification is required before
any of the options below is built.

## Governing rules (with evidence)

- **One grant exists.** Engine 10 blueprint §1.3 and §1.4.4: Engine 10 "never reads an ungranted source". Only a
  grant named in the source engine's own adopted document counts. The one grant today is Engine 5's: read-only
  access to its formula matrix, rate card rules and historical execution ledger, for what-if pricing.
- **Article 33.** TBOC Art.33, quoted in the Engine 10 blueprint: "No engine reads or writes another engine's
  tables; cross-engine truth moves only as a signal."
- **Snapshots only.** Engine 10 §1.4.1: every input is copied into `model_input_snapshot` before a run; a scenario
  never joins a live domain table.
- **Engines 7/8.** They are the exclusive transport for `SCENARIO_RUN_REQUESTED` and `SCENARIO_RUN_COMPLETED`.

## The three scenarios that cannot run

The runtime answers `NO_LAWFUL_READ_GRANT` for all three, which is correct.

| Scenario | What it must project | Data it needs | Authoritative owner | Grant today |
|---|---|---|---|---|
| FLEET_EXPANSION (capacity) | Capacity, utilisation and maintenance-cost impact of adding units | Units by class and estate; availability-ledger utilisation; maintenance cost history | Engine 2 (`resource_workforce_unit`, `resource_availability_ledger`, `resource_maintenance_record`); Engine 7 already keeps an aggregate (`orch_capacity_snapshot`) | None |
| PEAK_DEMAND (operational) | Dispatch and SLA outcomes under a demand surge | Orders per hour and class; time to quote, dispatch and arrival; SLA breaches | Engine 4 (orders, jobs); Engine 7 (SLA checks); Engine 2 (availability) | None |
| ZONE_IMPACT (operational) | Dispatch efficiency and coverage of a zone change | Zone geometry; per-zone demand and dispatch times; service coverage | Engine 5 (`cost_operational_zones`, outside its current grant); Engine 4 (orders by zone); Engine 3 (`service_coverage_zone`) | None |

Implementation note: the PRICING_CHANGE and COST_VS_CAPACITY runs read Engine 5's `cost_registry`, `cost_rate`
and `cost_record`. These are this rebuild's names for the granted rate-card and execution-ledger data. That
mapping should be confirmed when Engine 5's grant text is next amended.

## Options (least privilege first)

| Option | What changes | Privilege | Fits Art.33 and Engines 7/8 |
|---|---|---|---|
| **1. Aggregate snapshot signals (recommended)** | Each source engine's document grants Engine 10 a named **aggregate** it already computes or can compute, published as a signal through Engines 7/8 into `model_input_snapshot`. Engine 2: daily capacity and utilisation by class and estate (Engine 7's existing `orch_capacity_snapshot` is the model). Engine 4: hourly demand and dispatch timings by class and zone. Engine 3: coverage by zone. | Aggregates only; no row-level or personal data; no direct reads | Yes |
| 2. Read-only views per source engine | Each owner exposes a narrow view to Engine 10's role | Row-level access to operational data; a standing cross-engine read | Weaker: contradicts "never reads another engine's tables" |
| 3. Leave the three scenarios unavailable | Nothing; the screen keeps saying why | None | Yes |

**Recommendation.** Option 1, one scenario at a time, starting with FLEET_EXPANSION. Its aggregate (capacity by
class) already exists in Engine 7. Each grant is a Founder-approved amendment to the source engine's document,
followed by the signal, the snapshot writer and a test.

**Decision requested.** Approve Option 1 for FLEET_EXPANSION, or choose Option 3 for now.
