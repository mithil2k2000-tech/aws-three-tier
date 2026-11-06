# ADR-0002: CloudFront in front of an internal ALB through a VPC origin

**Status:** Accepted

## Context
- HTTPS normally needs a domain and an ACM certificate on a public ALB.
- The AWS Free plan account used for the earlier FinTech project cannot register domains in Route 53, and that blocked the deployment.
- A public ALB is also an extra internet-facing surface, with a public IPv4 charge per AZ.

## Decision
- Viewers connect to CloudFront over HTTPS using its default `*.cloudfront.net` certificate.
- CloudFront reaches an **internal** ALB through a CloudFront VPC origin.
- The ALB security group admits only the CloudFront origin-facing managed prefix list.
- Static files come from a private S3 bucket through Origin Access Control.
- A custom domain is optional: set `aliases` and `acm_certificate_arn`, and the minimum TLS version becomes TLSv1.2_2021.

## Consequences
- HTTPS works without owning a domain. The ALB has no public IP and cannot be reached directly from the internet.
- The hop from CloudFront to the ALB is HTTP inside AWS's network. Checkov's ALB-HTTPS checks are skipped with a reference to this ADR. Adding an ACM certificate to the ALB would make that hop TLS too, but needs a domain.
- With the default certificate, CloudFront allows TLS 1.0 and above for viewers. Use a custom domain to enforce TLS 1.2.
- VPC origins need an internet gateway in the VPC. We have one for the NAT gateway anyway.
