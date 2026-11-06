# Deploying

## 1. Bootstrap (once, as an administrator)
In AWS CloudShell or locally with admin credentials:
```bash
cd bootstrap
terraform init
terraform apply -var github_repo=<owner>/<repo>
# If the account already has the GitHub OIDC provider: -var create_oidc_provider=false
# If GitHub issues ID-qualified subjects: -var 'github_subject_prefix=repo:<owner>@<id>/<repo>@<id>'
```
Then move the bootstrap state into the bucket it created. Add a `backend "s3"` block with key `bootstrap.tfstate` and run `terraform init -migrate-state`.

## 2. GitHub settings
- **Variables** (Settings > Secrets and variables > Actions > Variables). None of them are secrets:

  | Variable | Value |
  |---|---|
  | `AWS_REGION` | `eu-west-2` |
  | `AWS_PLAN_ROLE_ARN` | bootstrap output `plan_role_arn` |
  | `AWS_DEPLOY_ROLE_ARN` | bootstrap output `deploy_role_arn` |
  | `TF_STATE_BUCKET` | bootstrap output `state_bucket` |
  | `ECR_REPOSITORY_URL` | bootstrap output `ecr_repository_url` |
  | `OWNER_EMAIL` | your email (alerts and budget) |
  | `TEARDOWN_FRIENDLY` | `true` for demos |

- **Environments:**
  - `prod-plan`: no protection.
  - `prod`: add yourself as a required reviewer, and allow deployments from `main` only.

## 3. Deploy
1. Go to **Actions > deploy > Run workflow** and type `deploy`.
2. Approve the `prod` environment when asked.
3. The run then:
   - builds the ARM64 image, scans it and pushes it;
   - plans, then applies that saved plan;
   - publishes the frontend;
   - waits for ECS;
   - smoke-tests `https://<id>.cloudfront.net/api/healthz`.
4. The URL appears in the run log (`terraform output url`).

The first apply takes about 15 minutes. RDS and CloudFront are the slow parts.

Confirm the SNS subscription email so that alarms reach you.

## 4. Tear down
Go to **Actions > destroy** and type `destroy`. Bootstrap resources are kept.
