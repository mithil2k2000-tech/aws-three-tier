# ADR-0004: Cost-aware defaults with resilience switches

**Status:** Accepted

## Context
This is a portfolio environment, paid for personally, and run for demos. The Well-Architected reliability guidance (one NAT per AZ, Multi-AZ database, WAF) roughly doubles the monthly cost.

## Decision
- **Defaults:**
  - one NAT gateway;
  - a single-AZ db.t4g.micro;
  - WAF off;
  - 30-day log retention;
  - two Fargate tasks in two AZs.
- **Switches** for the resilient setup: `nat_gateways = 2`, `multi_az_db = true`, `enable_waf = true`.
- `teardown_friendly = true` removes deletion protection and the final snapshot so `destroy` cleans up in one run.

## Consequences
- **What breaks in an AZ outage:**
  - If the AZ holding the NAT fails, tasks can no longer pull images or reach Secrets Manager. Running tasks keep serving.
  - If the database's AZ fails, the API is down until RDS recovers.
- The [Well-Architected review](../well-architected.md) records these as accepted risks, with the switch that fixes each.
