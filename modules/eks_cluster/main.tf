# Required for public ECR where Karpenter artifacts are hosted
provider "aws" {
  region = "us-east-1"
  alias  = "virginia"
}

data "aws_partition" "current" {}

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
data "aws_secretsmanager_secret" "argocd" {
  name = "${local.argocd_secret_manager_name}.${local.environment}"
}

data "aws_secretsmanager_secret_version" "admin_password_version" {
  secret_id = data.aws_secretsmanager_secret.argocd.id
}
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
  aws_auth_roles = flatten([
    module.eks_blueprints_platform_teams.aws_auth_configmap_role,
    [for team in module.eks_blueprints_dev_teams : team.aws_auth_configmap_role],
    {
      rolearn  = module.karpenter.role_arn
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
  ])

  # cluster_addons = {
  #   coredns    = {
  #     most_recent = true
  #   }
  #   kube-proxy = {
  #     most_recent = true
  #   }  
  #   aws-ebs-csi-driver = {
  #     most_recent = true
  #   }      
  #   vpc-cni = {
  #     # Specify the VPC CNI addon should be deployed before compute to ensure
  #     # the addon is configured before data plane compute resources are created
  #     # See README for further details
  #     before_compute = true
  #     most_recent    = true # To ensure access to the latest settings provided
  #     configuration_values = jsonencode({
  #       env = {
  #         # Reference docs https://docs.aws.amazon.com/eks/latest/userguide/cni-increase-ip-addresses.html
  #         ENABLE_PREFIX_DELEGATION = "true"
  #         WARM_PREFIX_TARGET       = "1"
  #       }
  #     })
  #   }
  # }

  tags = merge(local.tags, {
    # NOTE - if creating multiple security groups with this module, only tag the
    # security group that Karpenter should utilize with the following tag
    # (i.e. - at most, only one security group should have this tag in your account)
    "karpenter.sh/discovery" = "${local.environment}-${local.service}"
  })
}

data "aws_iam_role" "eks_admin_role_name" {
  count     = local.eks_admin_role_name != "" ? 1 : 0
  name = local.eks_admin_role_name
}

module "eks_blueprints_platform_teams" {
  source  = "aws-ia/eks-blueprints-teams/aws"
  version = "~> 0.2"

  name = "team-platform"

  # Enables elevated, admin privileges for this team
  enable_admin = true
 
  # Define who can impersonate the team-platform Role
  users             = [
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
  version = "~> 0.2"

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
# GitOps Bridge: Metadata
################################################################################
module "gitops_bridge_metadata" {
  source = "../../../gitops-bridge/argocd/iac/terraform/modules/gitops-bridge-metadata"

  cluster_name = module.eks.cluster_name
  metadata = merge(module.eks_blueprints_addons.gitops_metadata, {
    metadata_argocd_password = bcrypt(data.aws_secretsmanager_secret_version.admin_password_version.secret_string)
    metadata_seb_proute = "yes"
  })
  environment = local.environment
  addons = local.addons
}

################################################################################
# GitOps Bridge: Bootstrap
################################################################################
locals {
  kubeconfig = "/tmp/${module.eks.cluster_name}"
  argocd_bootstrap_control_plane = "https://raw.githubusercontent.com/allamand/gitops-bridge-argocd-control-plane-template/main/bootstrap/control-plane/exclude/bootstrap.yaml"
  argocd_bootstrap_workloads = "https://raw.githubusercontent.com/allamand/gitops-bridge-argocd-control-plane-template/main/bootstrap/workloads/exclude/bootstrap.yaml"
}
module "gitops_bridge_bootstrap" {
  source = "../../../gitops-bridge/argocd/iac/terraform/modules/gitops-bridge-bootstrap"

  options = {
    argocd = {
      cluster_name = module.eks.cluster_name
      argocd_create_install = true
      kubeconfig_command = <<-EOT
      KUBECONFIG=${local.kubeconfig}
      aws eks --region ${local.region} update-kubeconfig --name ${module.eks.cluster_name}
      EOT
      argocd_cluster = module.gitops_bridge_metadata.argocd
      argocd_bootstrap_app_of_apps = <<-EOT
      argocd app create --port-forward -f ${local.argocd_bootstrap_control_plane}
      argocd app create --port-forward -f ${local.argocd_bootstrap_workloads}
      EOT
    }
  }
}

module "eks_blueprints_addons" {
  source = "github.com/csantanapr/terraform-aws-eks-blueprints-addons?ref=gitops-bridge-v2"

  cluster_name      = module.eks.cluster_name
  cluster_endpoint  = module.eks.cluster_endpoint
  cluster_version   = module.eks.cluster_version
  oidc_provider_arn = module.eks.oidc_provider_arn
  vpc_id            = data.aws_vpc.vpc.id

  # Using GitOps Bridge
  create_kubernetes_resources    = false

  eks_addons = {
    aws-ebs-csi-driver = {
      most_recent = true
    }
    coredns = {
      most_recent = true
    }
    vpc-cni = {
      # Specify the VPC CNI addon should be deployed before compute to ensure
      # the addon is configured before data plane compute resources are created
      # See README for further details
      #service_account_role_arn = module.vpc_cni_irsa.iam_role_arn
      before_compute = true
      addon_version = "v1.12.2-eksbuild.1"
      #most_recent    = true # To ensure access to the latest settings provided
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

  #enable_aws_efs_csi_driver                    = true
  #enable_aws_fsx_csi_driver                    = true
  enable_aws_cloudwatch_metrics = true
  #enable_aws_privateca_issuer                  = true
  enable_cert_manager       = true
  #enable_cluster_autoscaler = true
  #enable_external_dns                          = true
  #external_dns_route53_zone_arns = ["arn:aws:route53:::hostedzone/Z123456789"]
  #enable_external_secrets                      = true
  enable_aws_load_balancer_controller = true
  enable_aws_for_fluentbit            = true
  #enable_fargate_fluentbit            = true
  #enable_aws_node_termination_handler   = true
  #aws_node_termination_handler_asg_arns = [for asg in module.eks.self_managed_node_groups : asg.autoscaling_group_arn]
  enable_karpenter = true
  #enable_velero = true
  ## An S3 Bucket ARN is required. This can be declared with or without a Suffix.
  #velero = {
  #  s3_backup_location = "${module.velero_backup_s3_bucket.s3_bucket_arn}/backups"
  #}
  #enable_aws_gateway_api_controller = true

  tags = local.tags
}

# module "kubernetes_addons" {
#   #source = "github.com/aws-ia/terraform-aws-eks-blueprints?ref=v4.32.0/modules/kubernetes-addons"
#   source = "github.com/aws-ia/terraform-aws-eks-blueprints?ref=blueprints-workshops/modules/kubernetes-addons"

#   eks_cluster_id     = module.eks.cluster_name

#   #---------------------------------------------------------------
#   # ARGO CD ADD-ON
#   #---------------------------------------------------------------

#   enable_argocd         = true
#   argocd_manage_add_ons = true # Indicates that ArgoCD is responsible for managing/deploying Add-ons.

#   argocd_applications = {
#     addons    = local.addons_application
#     workloads = local.workload_application #We comment it for now
#   }

#   argocd_helm_config = {
#     set_sensitive = [
#       {
#         name  = "configs.secret.argocdServerAdminPassword"
#         value = bcrypt(data.aws_secretsmanager_secret_version.admin_password_version.secret_string)
#       }
#     ]      
#     set = [
#       {
#         name  = "server.service.type"
#         value = "LoadBalancer"
#       }
#     ]
#   }

#   #---------------------------------------------------------------
#   # EKS Managed AddOns
#   # https://aws-ia.github.io/terraform-aws-eks-blueprints/add-ons/
#   #---------------------------------------------------------------

#   enable_amazon_eks_coredns = true
#   enable_amazon_eks_kube_proxy = true
#   enable_amazon_eks_vpc_cni = true      
#   enable_amazon_eks_aws_ebs_csi_driver = true
  
#   #---------------------------------------------------------------
#   # ADD-ONS - You can add additional addons here
#   # https://aws-ia.github.io/terraform-aws-eks-blueprints/add-ons/
#   #---------------------------------------------------------------


#   enable_aws_load_balancer_controller  = true
#   enable_aws_for_fluentbit             = true
#   enable_metrics_server                = true
#   enable_argo_rollouts                 = true # <-- Add this line
#   enable_karpenter                     = true # <-- Add this line 
#   karpenter_node_iam_instance_profile        = module.karpenter.instance_profile_name
#   karpenter_enable_spot_termination_handling = true
  
#   enable_kubecost                      = true
#   enable_ingress_nginx                 = true    
# }

################################################################################
# Karpenter
################################################################################

# Creates Karpenter native node termination handler resources and IAM instance profile
module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "~> 19.15.2"

  cluster_name           = module.eks.cluster_name
  irsa_oidc_provider_arn = module.eks.oidc_provider_arn
  create_irsa            = false # IRSA will be created by the kubernetes-addons module
  enable_spot_termination = true
  queue_managed_sse_enabled = true


  tags = local.tags
}  

resource "aws_security_group_rule" "alb" {
  security_group_id = module.eks.cluster_primary_security_group_id
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  description       = "Ingress from environment ALB security group"
  source_security_group_id = data.aws_security_group.alb_sg[0].id
}

