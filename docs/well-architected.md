# AWS Well-Architected review

A self-review against the six pillars of the AWS Well-Architected Framework. Each row names the design choice, where it is implemented, and any accepted risk. "Gap" items are deliberate trade-offs ([ADR-0004](adr/0004-cost-defaults.md)) or next steps.

## 1. Operational excellence

| Practice | Implementation | Where |
|---|---|---|
| Everything as code | All infrastructure in Terraform modules; bootstrap stack for the state bucket, ECR and IAM | `modules/`, `bootstrap/` |
| Small, reversible changes | Immutable image tags (commit SHA); ECS rolling deploy with circuit breaker and automatic rollback | `modules/app/main.tf` |
| Pre-deploy checks | fmt, validate, tflint, Checkov, Trivy config and image, Gitleaks, unit tests, pip-audit; plan on every PR | `.github/workflows/ci.yml` |
| Observability | Dashboard (traffic, errors, p50/p95/p99 latency, ECS, RDS); structured JSON logs; error metric filter | `modules/observability` |
| Practise failure | Game day: ship a broken release and watch the automatic rollback | [game-day.md](game-day.md) |
| Gap | No runbook automation (e.g. SSM documents); single environment | — |

## 2. Security

| Practice | Implementation |
|---|---|
| Identity | No long-lived keys: GitHub OIDC; separate read-only plan role and bounded deploy role ([ADR-0003](adr/0003-bounded-deploy-role.md)); ECS task role with no permissions |
| Network | Three subnet tiers; data tier has no internet route and a VPC-only NACL; chained security groups; internal ALB reachable only from CloudFront; default SG emptied |
| Data protection | KMS CMK with rotation for logs, RDS, secret and SNS; TLS to viewers and to the DB (`rds.force_ssl`); TLS-only bucket policies; no public buckets |
| Secrets | RDS-managed password in Secrets Manager, injected at runtime ([ADR-0005](adr/0005-rds-managed-password.md)) |
| Workload | Non-root (UID 10001), read-only root filesystem, all Linux capabilities dropped, no ECS Exec |
| Edge | CloudFront managed security headers (HSTS, X-Content-Type-Options, X-Frame-Options, Referrer-Policy); optional WAF with AWS managed rules and per-IP rate limit |
| Detection | GuardDuty with medium-plus findings routed to email; VPC flow logs; ALB access logs; RDS connection logging |
| Gap | WAF off by default (cost); viewers can negotiate TLS 1.0 on the default CloudFront certificate (fixed with a custom domain) |

## 3. Reliability

| Practice | Implementation |
|---|---|
| Multi-AZ application | ≥2 tasks across 2 AZs; ALB health checks; ECS replaces failed tasks |
| Scaling | Target tracking at 60% CPU, 2 to 4 tasks |
| Safe deploys | `minimum_healthy_percent = 100`, circuit breaker with rollback |
| Backups | RDS automated backups, 7 days, point-in-time restore; final snapshot unless `teardown_friendly`; deletion protection |
| Storage | gp3 with storage autoscaling up to 5× |
| Accepted risks (defaults) | Single NAT (`nat_gateways = 2` fixes it); single-AZ DB (`multi_az_db = true` fixes it); single region |

## 4. Performance efficiency

| Practice | Implementation |
|---|---|
| Right compute | Fargate ARM64 0.25 vCPU / 0.5 GB; sizes are variables |
| Edge caching | Static files cached at CloudFront (CachingOptimized); API uncached; HTTP/2 and HTTP/3; compression |
| Connection reuse | psycopg connection pool (1–5 per task) |
| Measure | p95 latency alarm; p50/p95/p99 on the dashboard |
| Gap | No load test yet; db.t4g is burstable (watch CPU credits) |

## 5. Cost optimisation

| Practice | Implementation |
|---|---|
| Pay for what runs | Fargate; no EKS control plane; free S3 gateway endpoint so image layers skip NAT data charges |
| Cheaper silicon | Graviton for Fargate and RDS |
| No idle public IPs | Internal ALB (only the NAT has a public IPv4 address) |
| Guardrails | AWS Budget with 80% actual and 100% forecast alerts; destroy workflow; `teardown_friendly` |
| Lifecycle | Log retention 30 days; ALB logs expire after 90 days; old site versions after 30; ECR keeps 20 images |
| Details | [cost.md](cost.md) |

## 6. Sustainability

| Practice | Implementation |
|---|---|
| Efficient hardware | Graviton (ARM64) for compute and database |
| Utilisation | Autoscaling instead of peak provisioning; small task size |
| Less data moved | CloudFront caching and compression; S3 gateway endpoint |
| Turn it off | Designed to be destroyed when not demoing |
| Region | London (eu-west-2) for UK users; choose a region with a lower-carbon grid if latency allows |
