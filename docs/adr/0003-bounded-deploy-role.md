# ADR-0003: Deploy role limited by a permissions boundary

**Status:** Accepted

## Context
Infrastructure pipelines often run as AdministratorAccess. If such a pipeline is compromised, the whole account is compromised, including the ability to create an admin user for persistence.

## Decision
- The deploy role has `PowerUserAccess`, which includes no IAM.
- Added to that, an inline policy allows:
  - creating roles only under `/app/three-tier/`, and only if they carry the `three-tier-workload-boundary` policy;
  - passing those roles only to ECS, VPC Flow Logs and RDS monitoring;
  - creating service-linked roles only for named services.
- It explicitly denies removing boundaries and editing policy versions.
- Both GitHub roles trust only specific OIDC subjects. Deploy is trusted only from the `prod` environment, which needs a reviewer.

## Consequences
- A compromised pipeline cannot create an administrator or escalate through IAM. Every role it creates is capped by the boundary (logs, ECR pull, one secret, one key, metrics).
- New AWS services that need extra IAM permissions require a reviewed change to the bootstrap stack.
- `PowerUserAccess` is still broad for data-plane actions. A stricter setup would list the services this stack uses.
