# Cost

These are approximate on-demand prices for London (eu-west-2) with the default settings. Prices change, so check the AWS Pricing Calculator before you deploy.

| Item | Default | ≈ per day | ≈ per month |
|---|---|---|---|
| NAT gateway (1) + its public IPv4 | on | $1.30 | $39 |
| Application Load Balancer (internal) | on | $0.65 | $20 |
| Fargate: 2 tasks × 0.25 vCPU / 0.5 GB ARM64 | on | $0.55 | $17 |
| RDS db.t4g.micro single-AZ + 20 GB gp3 | on | $0.50 | $15 |
| KMS key, Secrets Manager secret, 8 alarms, dashboard, logs | on | $0.25 | $7 |
| CloudFront, S3 | on | ~$0 | within free tier at demo traffic |
| GuardDuty | on | free for 30 days, then usage-based | |
| **Total (defaults)** | | **≈ $3.25** | **≈ $100** |
| + second NAT (`nat_gateways = 2`) | off | +$1.30 | +$39 |
| + Multi-AZ database | off | +$0.45 | +$13 |
| + WAF | off | +$0.25 plus requests | +$8 plus requests |

## How to keep it cheap
- Deploy, demo, then run **destroy**. A three-hour demo costs well under $1.
- Keep `teardown_friendly = true` for demos, so destroy removes the database and ALB without manual steps.
- The bootstrap stack (state bucket, ECR, IAM) costs pennies and can stay.
- The budget alerts email you at 80% of the monthly limit and when the forecast passes 100%.
