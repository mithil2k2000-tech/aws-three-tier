# ADR-0005: RDS-managed master password in Secrets Manager

**Status:** Accepted

## Decision
- Use `manage_master_user_password = true`, with the secret encrypted by the stack's KMS key.
- ECS injects `username` and `password` from that secret at task start, through the execution role, which may read only that secret.

## Consequences
- The password is never in Terraform state, tfvars, GitHub or container images. Rotation is automatic.
- The app uses the master user for simplicity. Next step: a least-privilege application role created by a migration, or IAM database authentication (already enabled on the instance).
