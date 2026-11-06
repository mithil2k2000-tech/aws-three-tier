# ADR-0006: S3 backend with native state locking

**Status:** Accepted

## Decision
Use the S3 backend with `use_lockfile = true` (Terraform 1.10 and later) instead of a DynamoDB lock table. The bucket is versioned, encrypted, TLS-only and blocks public access. Old state versions expire after 90 days.

## Consequences
- There is one less resource to create and pay for. Locking still prevents two runs applying at once.
- Terraform 1.10 or later is required. CI pins 1.13.4.
