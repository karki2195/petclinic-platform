# Root module for the dev environment.
# Module calls are wired in as each epic is implemented (see docs/jira-backlog.md):
#   E-2 Networking   -> module "vpc"
#   E-3 EKS Cluster  -> module "eks"
#   E-4 ECR          -> module "ecr"
#   E-5 RDS          -> module "rds"
#   E-6 DNS/Ingress  -> module "dns"
#   E-7 Secrets Mgr  -> module "secrets"
#   E-11 Observability -> module "observability"
