# ADR-0001: ECS on Fargate for the application tier

**Status:** Accepted

## Context
The API is one stateless container. The options were EC2 Auto Scaling groups, EKS, ECS on EC2, and ECS on Fargate.

## Decision
ECS on Fargate, ARM64 (Graviton), at least two tasks across two AZs, with target-tracking autoscaling on CPU.

## Consequences
- There are no hosts to patch, and no control-plane fee (EKS charges per cluster-hour).
- Graviton costs about 20% less than x86 Fargate and uses less energy (sustainability pillar). The image must be built for ARM64, which is why CI uses an ARM runner.
- Kubernetes portability is lost. The separate Kubernetes project covers that skill.
