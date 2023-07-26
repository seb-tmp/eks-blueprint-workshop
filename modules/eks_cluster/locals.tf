locals {
  environment = var.environment_name
  service     = var.service_name
  region      = var.aws_region

  env  = local.environment
  name = "${local.environment}-${local.service}"

  # Mapping
  cluster_version            = var.cluster_version
  argocd_secret_manager_name = var.argocd_secret_manager_name_suffix
  eks_admin_role_name        = var.eks_admin_role_name
  addons_repo_url            = var.addons_repo_url  
  workload_repo_path         = var.workload_repo_path
  workload_repo_url          = var.workload_repo_url
  workload_repo_revision     = var.workload_repo_revision  

  tag_val_vpc            = local.environment
  tag_val_public_subnet  = "${local.environment}-public-"
  tag_val_private_subnet = "${local.environment}-private-"

  node_group_name = "managed-ondemand"

  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/aws-ia/terraform-aws-eks-blueprints"
  }
  
  #---------------------------------------------------------------
  # ARGOCD ADD-ON APPLICATION
  #---------------------------------------------------------------

  addons = {
    #enable_prometheus_adapter                    = true # doesn't required aws resources (ie IAM)
    #enable_gpu_operator                          = true # doesn't required aws resources (ie IAM)
    #enable_kyverno                               = true # doesn't required aws resources (ie IAM)
    #enable_argo_rollouts                         = true # doesn't required aws resources (ie IAM)
    #enable_argo_workflows                        = true # doesn't required aws resources (ie IAM)
    #enable_secrets_store_csi_driver              = true # doesn't required aws resources (ie IAM)
    #enable_secrets_store_csi_driver_provider_aws = true # doesn't required aws resources (ie IAM)
    #enable_kube_prometheus_stack                 = true # doesn't required aws resources (ie IAM)
    #enable_gatekeeper                            = true # doesn't required aws resources (ie IAM)
    #enable_ingress_nginx                         = true # doesn't required aws resources (ie IAM)
    enable_metrics_server                        = true # doesn't required aws resources (ie IAM)
    #enable_vpa                                   = true # doesn't required aws resources (ie IAM)
    #aws_enable_ebs_csi_resources                 = true # generate gp2 and gp3 storage classes for ebs-csi
    #enable_prometheus_adapter                    = true # doesn't required aws resources (ie IAM)
    #enable_gpu_operator                          = true # doesn't required aws resources (ie IAM)
    enable_foo                                   = true # you can add any addon here, make sure to update the gitops repo with the corresponding application set
  }

  #At this time (with new v5 addon repository), the Addons need to be managed by Terrform and not ArgoCD
  # addons_application = {
  #   path                = "chart"
  #   repo_url            = local.addons_repo_url
  #   add_on_application  = true
  # }

  #---------------------------------------------------------------
  # ARGOCD WORKLOAD APPLICATION
  #---------------------------------------------------------------

  # workload_application = {
  #   path                = local.workload_repo_path # <-- we could also to blue/green on the workload repo path like: envs/dev-blue / envs/dev-green
  #   repo_url            = local.workload_repo_url
  #   target_revision     = local.workload_repo_revision

  #   add_on_application  = false
    
  #   values = {
  #     labels = {
  #       env   = local.env
  #     }
  #     spec = {
  #       source = {
  #         repoURL        = local.workload_repo_url
  #         targetRevision = local.workload_repo_revision
  #       }
  #       blueprint                = "terraform"
  #       clusterName              = local.name
  #       karpenterInstanceProfile = module.karpenter.instance_profile_name # Activate to enable Karpenter manifests (only when Karpenter add-on will be enabled in the Karpenter workshop)
  #       env                      = local.env
  #       target_group_arn         = local.service == "blue" ? data.aws_lb_target_group.tg_blue.arn : data.aws_lb_target_group.tg_green.arn # <-- Add this line        
  #     }
  #   }
  # }  

}


data "aws_lb_target_group" "tg_blue" {
  name = "${local.environment}-tg-blue"
}

data "aws_lb_target_group" "tg_green" {
  name = "${local.environment}-tg-green"
}

data "aws_lb" "alb" {
  name = "${local.environment}-alb"
}

data "aws_security_group" "alb_sg" {
  count = 1
  id    = tolist(data.aws_lb.alb.security_groups)[count.index]
}

