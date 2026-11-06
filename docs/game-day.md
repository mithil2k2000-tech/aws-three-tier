# Game day: a deliberately broken release

**Goal:** show that a bad release is detected and rolled back automatically, that alerts fire, and that the team can explain what happened from telemetry alone.

**Status:** procedure ready. It has not yet been run against a live environment. Fill in the report section after the first run.

## Hypothesis
If a release fails its health check:
- ECS stops the rollout and restores the previous task definition (deployment circuit breaker);
- users keep getting answers from the old tasks throughout, because `minimum_healthy_percent = 100`;
- the `unhealthy-targets` alarm emails the on-call address.

## Steps
1. Check the steady state:
   - the dashboard is green;
   - `curl https://<url>/api/healthz` shows the current version;
   - start a probe: `while true; do curl -s -o /dev/null -w "%{http_code} " https://<url>/api/healthz; sleep 2; done`.
2. Go to **Actions > deploy** and type `deploy`, with **broken_release** ticked. The image is tagged `<sha>-broken` and its `/api/healthz` returns 503.
3. Watch:
   - ECS console > service > Deployments (rollout state);
   - target group health;
   - the probe output;
   - your inbox.
4. Expected:
   - the new tasks fail their health checks;
   - the circuit breaker marks the rollout `FAILED` and rolls back;
   - the probe keeps returning 200;
   - the alarm emails go out: ALARM, then OK.
5. Gather evidence:
   - `aws ecs describe-services ... --query 'services[0].events[:20]'`;
   - a dashboard screenshot;
   - the alarm history.
6. Clean up: run a normal deploy. Terraform state still references the broken image tag until you do.

## Report template

| | |
|---|---|
| Date and duration | |
| Impact on users | (probe: number of non-200s) |
| Detection | (time of first alarm, which alarm) |
| Automatic response | (time circuit breaker triggered, time rollback completed) |
| Timeline | (UTC: deploy started, first failed health check, rollout FAILED, rollback complete, alarm OK) |
| What went well | |
| What surprised us | |
| Actions | (owner, due date) |
