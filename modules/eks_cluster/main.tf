# Required for public ECR where Karpenter artifacts are hosted
provider "aws" {
  region = "us-east-1"
  alias  = "virginia"
}

# Find the user currently in use by AWS
data "aws_caller_identity" "current" {}

data "aws_vpc" "vpc" {
  filter {
    name   = "tag:Name"
    values = [local.tag_val_vpc]
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "tag:Name"
    values = ["${local.tag_val_private_subnet}*"]
  }
}

#Add Tags for the new cluster in the VPC Subnets
resource "aws_ec2_tag" "private_subnets" {
  for_each    = toset(data.aws_subnets.private.ids)
  resource_id = each.value
  key         = "kubernetes.io/cluster/${local.environment}-${local.service}"
  value       = "shared"
}

data "aws_subnets" "public" {
  filter {
    name   = "tag:Name"
    values = ["${local.tag_val_public_subnet}*"]
  }
}

#Add Tags for the new cluster in the VPC Subnets
resource "aws_ec2_tag" "public_subnets" {
  for_each    = toset(data.aws_subnets.public.ids)
  resource_id = each.value
  key         = "kubernetes.io/cluster/${local.environment}-${local.service}"
  value       = "shared"
}

################################################################################
# AWS Secret Manager for argocd password
################################################################################

data "aws_secretsmanager_secret" "argocd" {
  name = "${local.argocd_secret_manager_name}.${local.environment}"
}

data "aws_secretsmanager_secret_version" "admin_password_version" {
  secret_id = data.aws_secretsmanager_secret.argocd.id
}

################################################################################
# EKS Cluster
################################################################################
#tfsec:ignore:aws-eks-enable-control-plane-logging
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 19.15.2"

  cluster_name                   = local.name
  cluster_version                = local.cluster_version
  cluster_endpoint_public_access = true

  vpc_id     = data.aws_vpc.vpc.id
  subnet_ids = data.aws_subnets.private.ids

  #we uses only 1 security group to allow connection with Fargate, MNG, and Karpenter nodes
  create_node_security_group = false
  cluster_security_group_additional_rules = {
    ingress_alb_security_group_id = {
      description              = "Ingress from environment ALB security group"
      protocol                 = "tcp"
      from_port                = 80
      to_port                  = 80
      type                     = "ingress"
      source_security_group_id = data.aws_security_group.alb_sg[0].id
    }
  }

  eks_managed_node_groups = {
    initial = {
      node_group_name = local.node_group_name
      instance_types  = ["m5.large"]

      min_size     = 1
      max_size     = 5
      desired_size = 3
      subnet_ids   = data.aws_subnets.private.ids
    }
  }

  manage_aws_auth_configmap = true
  aws_auth_roles = concat(
    [for team in module.eks_blueprints_dev_teams : team.aws_auth_configmap_role],
    [
      module.eks_blueprints_platform_teams.aws_auth_configmap_role,
      {
        rolearn  = module.eks_blueprints_addons.karpenter.node_iam_role_arn
        username = "system:node:{{EC2PrivateDNSName}}"
        groups = [
          "system:bootstrappers",
          "system:nodes",
        ]
      },
      {
        rolearn  = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.eks_admin_role_name}" # The ARN of the IAM role
        username = "ops-role"                                                                                      # The user name within Kubernetes to map to the IAM role
        groups   = ["system:masters"]                                                                              # A list of groups within Kubernetes to which the role is mapped; Checkout K8s Role and Rolebindings
      }
    ]
  )

  tags = merge(local.tags, {
    # NOTE - if creating multiple security groups with this module, only tag the
    # security group that Karpenter should utilize with the following tag
    # (i.e. - at most, only one security group should have this tag in your account)
    "karpenter.sh/discovery" = "${local.environment}-${local.service}"
  })
}

data "aws_iam_role" "eks_admin_role_name" {
  count = local.eks_admin_role_name != "" ? 1 : 0
  name  = local.eks_admin_role_name
}

################################################################################
# Allow flow from VPC Lattice to EKS cluster
################################################################################

# Lookup VPC Lattice prefix list IDs
data "aws_ec2_managed_prefix_list" "vpc_lattice" {
  name = "com.amazonaws.${local.region}.vpc-lattice"
}

data "aws_ec2_managed_prefix_list" "vpc_lattice_ipv6" {
  name = "com.amazonaws.${local.region}.ipv6.vpc-lattice"
}

# Authorize ingress from prefix lists to EKS cluster security group
resource "aws_security_group_rule" "vpc_lattice_ingress" {
  security_group_id = module.eks.cluster_primary_security_group_id

  prefix_list_ids = [
    data.aws_ec2_managed_prefix_list.vpc_lattice.id,
    data.aws_ec2_managed_prefix_list.vpc_lattice_ipv6.id
  ]

  type      = "ingress"
  from_port = 0
  to_port   = 0
  protocol  = "-1"
}

################################################################################
# EKS Blueprints Teams
################################################################################
module "eks_blueprints_platform_teams" {
  source  = "aws-ia/eks-blueprints-teams/aws"
  version = "~> 1.0"

  name = "team-platform"

  # Enables elevated, admin privileges for this team
  enable_admin = true

  # Define who can impersonate the team-platform Role
  users = [
    data.aws_caller_identity.current.arn,
    try(data.aws_iam_role.eks_admin_role_name[0].arn, data.aws_caller_identity.current.arn),
  ]
  cluster_arn       = module.eks.cluster_arn
  oidc_provider_arn = module.eks.oidc_provider_arn

  labels = {
    "elbv2.k8s.aws/pod-readiness-gate-inject" = "enabled",
    "appName"                                 = "platform-team-app",
    "projectName"                             = "project-platform",
  }

  annotations = {
    team = "platform"
  }

  namespaces = {
    "team-platform" = {

      resource_quota = {
        hard = {
          "requests.cpu"    = "10000m",
          "requests.memory" = "20Gi",
          "limits.cpu"      = "20000m",
          "limits.memory"   = "50Gi",
          "pods"            = "20",
          "secrets"         = "20",
          "services"        = "20"
        }
      }

      limit_range = {
        limit = [
          {
            type = "Pod"
            max = {
              cpu    = "1000m"
              memory = "1Gi"
            },
            min = {
              cpu    = "10m"
              memory = "4Mi"
            }
          },
          {
            type = "PersistentVolumeClaim"
            min = {
              storage = "24M"
            }
          }
        ]
      }

    }

  }

  tags = local.tags
}

module "eks_blueprints_dev_teams" {
  source  = "aws-ia/eks-blueprints-teams/aws"
  version = "~> 1.0"

  for_each = {
    burnham = {
      labels = {
        "elbv2.k8s.aws/pod-readiness-gate-inject" = "enabled",
        "appName"                                 = "burnham-team-app",
        "projectName"                             = "project-burnham",
      }
    }
    riker = {
      labels = {
        "elbv2.k8s.aws/pod-readiness-gate-inject" = "enabled",
        "appName"                                 = "riker-team-app",
        "projectName"                             = "project-riker",
      }
    }
  }
  name = "team-${each.key}"

  users             = [data.aws_caller_identity.current.arn]
  cluster_arn       = module.eks.cluster_arn
  oidc_provider_arn = module.eks.oidc_provider_arn

  labels = merge(
    {
      team = each.key
    },
    try(each.value.labels, {})
  )

  annotations = {
    team = each.key
  }

  namespaces = {
    "team-${each.key}" = {
      labels = merge(
        {
          team = each.key
        },
        try(each.value.labels, {})
      )

      resource_quota = {
        hard = {
          "requests.cpu"    = "100",
          "requests.memory" = "20Gi",
          "limits.cpu"      = "200",
          "limits.memory"   = "50Gi",
          "pods"            = "30",
          "secrets"         = "10",
          "services"        = "20"
        }
      }

      limit_range = {
        limit = [
          {
            type = "Pod"
            max = {
              cpu    = "2"
              memory = "1Gi"
            }
            min = {
              cpu    = "10m"
              memory = "4Mi"
            }
          },
          {
            type = "PersistentVolumeClaim"
            min = {
              storage = "24M"
            }
          },
          {
            type = "Container"
            default = {
              cpu    = "50m"
              memory = "24Mi"
            }
          }
        ]
      }
    }
  }

  tags = local.tags

}

################################################################################
# External-DNS - retrieve Hosted Zone
################################################################################
data "aws_route53_zone" "sub" {
  name         = local.hosted_zone_name
  private_zone = true
}

################################################################################
# GitOps Bridge: Private ssh keys for git
################################################################################
# Uncomment to uses git secret
# data "aws_secretsmanager_secret" "workload_repo_secret" {
#   name = local.aws_secret_manager_git_private_ssh_key_name
# }

# data "aws_secretsmanager_secret_version" "workload_repo_secret" {
#   secret_id = data.aws_secretsmanager_secret.workload_repo_secret.id
# }

resource "kubernetes_namespace" "argocd" {
  depends_on = [module.eks_blueprints_addons]
  metadata {
    name = "argocd"
  }
}

resource "kubernetes_secret" "git_secrets" {

  for_each = {
    git-addons = {
      type = "git"
      url  = local.gitops_addons_url
      # comment if you want to uses public repo wigh syntax "https://github.com/xxx" syntax, uncomment when using syntax "git@github.com:xxx"
      #sshPrivateKey = data.aws_secretsmanager_secret_version.workload_repo_secret.secret_string
    }
    git-workloads = {
      type = "git"
      url  = local.gitops_workloads_url
      # comment if you want to uses public repo wigh syntax "https://github.com/xxx" syntax, uncomment when using syntax "git@github.com:xxx"
      #sshPrivateKey = data.aws_secretsmanager_secret_version.workload_repo_secret.secret_string
    }
  }
  metadata {
    name      = each.key
    namespace = kubernetes_namespace.argocd.metadata[0].name
    labels = {
      "argocd.argoproj.io/secret-type" = "repo-creds"
    }
  }
  data = each.value
}

################################################################################
# GitOps Bridge: Bootstrap
################################################################################

module "gitops_bridge_bootstrap" {
  source = "github.com/gitops-bridge-dev/gitops-bridge-argocd-bootstrap-terraform?ref=v2.0.0"

  cluster = {
    cluster_name = module.eks.cluster_name
    environment  = local.environment
    metadata     = local.addons_metadata
    addons       = local.addons
  }
  apps = local.argocd_apps

  argocd = {
    create_namespace = false
    set = [
      {
        name  = "server.service.type"
        value = "LoadBalancer"
      }
    ]
    set_sensitive = [
      {
        name  = "configs.secret.argocdServerAdminPassword"
        value = bcrypt(data.aws_secretsmanager_secret_version.admin_password_version.secret_string)
      }
    ]
  }
  depends_on = [kubernetes_secret.git_secrets]
}

################################################################################
# EKS Blueprints Addons
################################################################################
module "eks_blueprints_addons" {
  #source = "aws-ia/eks-blueprints-addons/aws"
  #version = "~> 1.11.0" #ensure to update this to the latest/desired version
  source = "github.com/aws-ia/terraform-aws-eks-blueprints-addons?ref=gw_v1"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn

  # Using GitOps Bridge
  create_kubernetes_resources = false

  eks_addons = {

    # Remove for workshop as ebs-csi is long to provision (15mn)
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = module.ebs_csi_driver_irsa.iam_role_arn
    }
    coredns = {
      most_recent = true
    }
    vpc-cni = {
      # Specify the VPC CNI addon should be deployed before compute to ensure
      # the addon is configured before data plane compute resources are created
      # See README for further details
      service_account_role_arn = module.vpc_cni_irsa.iam_role_arn
      before_compute           = true
      #addon_version  = "v1.12.2-eksbuild.1"
      most_recent = true # To ensure access to the latest settings provided
      configuration_values = jsonencode({
        env = {
          # Reference docs https://docs.aws.amazon.com/eks/latest/userguide/cni-increase-ip-addresses.html
          ENABLE_PREFIX_DELEGATION = "true"
          WARM_PREFIX_TARGET       = "1"
        }
      })
    }
    kube-proxy = {
      most_recent = true
    }
  }

  # EKS Blueprints Addons
  enable_cert_manager                 = try(local.aws_addons.enable_cert_manager, false)
  enable_aws_efs_csi_driver           = try(local.aws_addons.enable_aws_efs_csi_driver, false)
  enable_aws_fsx_csi_driver           = try(local.aws_addons.enable_aws_fsx_csi_driver, false)
  enable_aws_cloudwatch_metrics       = try(local.aws_addons.enable_aws_cloudwatch_metrics, false)
  enable_aws_privateca_issuer         = try(local.aws_addons.enable_aws_privateca_issuer, false)
  enable_cluster_autoscaler           = try(local.aws_addons.enable_cluster_autoscaler, false)
  enable_external_dns                 = try(local.aws_addons.enable_external_dns, false)
  external_dns_route53_zone_arns      = try([data.aws_route53_zone.sub.arn], [])
  enable_external_secrets             = try(local.aws_addons.enable_external_secrets, false)
  enable_aws_load_balancer_controller = try(local.aws_addons.enable_aws_load_balancer_controller, false)
  aws_load_balancer_controller = {
    service_account_name = "aws-lb-sa"
  }
  enable_fargate_fluentbit                   = try(local.aws_addons.enable_fargate_fluentbit, false)
  enable_aws_for_fluentbit                   = try(local.aws_addons.enable_aws_for_fluentbit, false)
  enable_aws_node_termination_handler        = try(local.aws_addons.enable_aws_node_termination_handler, false)
  aws_node_termination_handler_asg_arns      = [for asg in module.eks.self_managed_node_groups : asg.autoscaling_group_arn]
  enable_karpenter                           = try(local.aws_addons.enable_karpenter, false)
  karpenter_enable_instance_profile_creation = false # Determines whether Karpenter will be allowed to create the IAM instance profile (v1beta1) or if Terraform will (v1alpha1)
  karpenter = {
    #karpenter_enable_instance_profile_creation = false
  }

  enable_velero = try(local.aws_addons.enable_velero, false)
  #velero = {
  #  s3_backup_location = "${module.velero_backup_s3_bucket.s3_bucket_arn}/backups"
  #}
  enable_aws_gateway_api_controller = try(local.aws_addons.enable_aws_gateway_api_controller, false)
  #enable_aws_secrets_store_csi_driver_provider = try(local.enable_aws_secrets_store_csi_driver_provider, false)

  tags = local.tags
}

module "ebs_csi_driver_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.20"

  role_name_prefix = "${module.eks.cluster_name}-ebs-csi-"

  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }

  tags = local.tags
}

################################################################################
# ACK Addons
################################################################################

module "eks_ack_addons" {
  #source = "aws-ia/eks-ack-addons/aws"
  #version = "2.1.0"
  source = "github.com/allamand/terraform-aws-eks-ack-addons?ref=ack_iam"


  # Cluster Info
  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  oidc_provider_arn = module.eks.oidc_provider_arn

  create_kubernetes_resources = false

  # Controllers to enable
  enable_iam         = try(local.aws_addons.enable_ack_iam, false)
  enable_eventbridge = try(local.aws_addons.enable_ack_eventbridge, false)

  tags = local.tags
}

module "vpc_cni_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.20"

  role_name_prefix = "${module.eks.cluster_name}-vpc-cni-"

  attach_vpc_cni_policy = true
  vpc_cni_enable_ipv4   = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:aws-node"]
    }
  }

  tags = local.tags
}

################################################################################
# Security group from external load Balancer defined in environment
# ################################################################################
data "external" "check_alb_security_group_rule_80" {
  program = ["${path.module}/check_aws_security_group_rule.sh", "80", module.eks.cluster_primary_security_group_id, data.aws_security_group.alb_sg[0].id]
}
data "external" "check_alb_security_group_rule_10254" {
  program = ["${path.module}/check_aws_security_group_rule.sh", "10254", module.eks.cluster_primary_security_group_id, data.aws_security_group.alb_sg[0].id]
}
resource "aws_security_group_rule" "alb" {
  count                    = data.external.check_alb_security_group_rule_80.result == "true" ? 0 : 1 # Create only if it doesn't exist
  security_group_id        = module.eks.cluster_primary_security_group_id
  type                     = "ingress"
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  description              = "Ingress from environment ALB security group"
  source_security_group_id = data.aws_security_group.alb_sg[0].id
}

resource "aws_security_group_rule" "alb_10254" {
  count                    = data.external.check_alb_security_group_rule_10254.result == "true" ? 0 : 1 # Create only if it doesn't exist
  security_group_id        = module.eks.cluster_primary_security_group_id
  type                     = "ingress"
  from_port                = 10254
  to_port                  = 10254
  protocol                 = "tcp"
  description              = "Ingress from environment ALB security group"
  source_security_group_id = data.aws_security_group.alb_sg[0].id
}
