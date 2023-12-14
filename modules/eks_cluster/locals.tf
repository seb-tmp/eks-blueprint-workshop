locals {
  environment = var.environment_name
  service     = var.service_name
  region      = var.aws_region

  env  = local.service
  name = "${local.environment}-${local.service}"

  hosted_zone_name = var.hosted_zone_name
  # Mapping
  #hosted_zone_name                            = var.hosted_zone_name
  ingress_type                                = var.ingress_type
  aws_secret_manager_git_private_ssh_key_name = var.aws_secret_manager_git_private_ssh_key_name
  cluster_version                             = var.cluster_version
  argocd_secret_manager_name                  = var.argocd_secret_manager_name_suffix
  eks_admin_role_name                         = var.eks_admin_role_name

  gitops_workloads_url      = "${var.gitops_workloads_org}/${var.gitops_workloads_repo}"
  gitops_workloads_path     = var.gitops_workloads_path
  gitops_workloads_revision = var.gitops_workloads_revision

  gitops_addons_url      = "${var.gitops_addons_org}/${var.gitops_addons_repo}"
  gitops_addons_basepath = var.gitops_addons_basepath
  gitops_addons_path     = var.gitops_addons_path
  gitops_addons_revision = var.gitops_addons_revision

  # Route 53 Ingress Weights
  # argocd_route53_weight      = var.argocd_route53_weight
  # route53_weight             = var.route53_weight
  # ecsfrontend_route53_weight = var.ecsfrontend_route53_weight

  eks_cluster_domain = local.hosted_zone_name # for external-dns

  lattice_default_service_network = "app-services-gw"

  tag_val_vpc            = local.environment
  tag_val_public_subnet  = "${local.environment}-public-"
  tag_val_private_subnet = "${local.environment}-private-"

  node_group_name = "managed-ondemand"

  #---------------------------------------------------------------
  # ARGOCD ADD-ON APPLICATION
  #---------------------------------------------------------------

  aws_addons = {
    enable_cert_manager                          = try(var.addons.enable_cert_manager, false)
    enable_aws_efs_csi_driver                    = try(var.addons.enable_aws_efs_csi_driver, false)
    enable_aws_fsx_csi_driver                    = try(var.addons.enable_aws_fsx_csi_driver, false)
    enable_aws_cloudwatch_metrics                = try(var.addons.enable_aws_cloudwatch_metrics, false)
    enable_aws_privateca_issuer                  = try(var.addons.enable_aws_privateca_issuer, false)
    enable_cluster_autoscaler                    = try(var.addons.enable_cluster_autoscaler, false)
    enable_external_dns                          = try(var.addons.enable_external_dns, false)
    enable_external_secrets                      = try(var.addons.enable_external_secrets, false)
    enable_aws_load_balancer_controller          = try(var.addons.enable_aws_load_balancer_controller, false)
    enable_fargate_fluentbit                     = try(var.addons.enable_fargate_fluentbit, false)
    enable_aws_for_fluentbit                     = try(var.addons.enable_aws_for_fluentbit, false)
    enable_aws_node_termination_handler          = try(var.addons.enable_aws_node_termination_handler, false)
    enable_karpenter                             = try(var.addons.enable_karpenter, false)
    enable_velero                                = try(var.addons.enable_velero, false)
    enable_aws_gateway_api_controller            = try(var.addons.enable_aws_gateway_api_controller, false)
    enable_aws_ebs_csi_resources                 = try(var.addons.enable_aws_ebs_csi_resources, false)
    enable_aws_secrets_store_csi_driver_provider = try(var.addons.enable_aws_secrets_store_csi_driver_provider, false)
    enable_ack_apigatewayv2                      = try(var.addons.enable_ack_apigatewayv2, false)
    enable_ack_dynamodb                          = try(var.addons.enable_ack_dynamodb, false)
    enable_ack_s3                                = try(var.addons.enable_ack_s3, false)
    enable_ack_rds                               = try(var.addons.enable_ack_rds, false)
    enable_ack_prometheusservice                 = try(var.addons.enable_ack_prometheusservice, false)
    enable_ack_emrcontainers                     = try(var.addons.enable_ack_emrcontainers, false)
    enable_ack_sfn                               = try(var.addons.enable_ack_sfn, false)
    enable_ack_eventbridge                       = try(var.addons.enable_ack_eventbridge, false)
    enable_ack_iam                               = try(var.addons.enable_ack_iam, false)
    enable_aws_argocd_ingress                    = try(var.addons.enable_aws_argocd_ingress, false)
  }
  oss_addons = {
    enable_argocd                          = try(var.addons.enable_argocd, true)
    enable_argo_rollouts                   = try(var.addons.enable_argo_rollouts, false)
    enable_argo_events                     = try(var.addons.enable_argo_events, false)
    enable_argo_workflows                  = try(var.addons.enable_argo_workflows, false)
    enable_cluster_proportional_autoscaler = try(var.addons.enable_cluster_proportional_autoscaler, false)
    enable_gatekeeper                      = try(var.addons.enable_gatekeeper, false)
    enable_gpu_operator                    = try(var.addons.enable_gpu_operator, false)
    enable_ingress_nginx                   = try(var.addons.enable_ingress_nginx, false)
    enable_kyverno                         = try(var.addons.enable_kyverno, false)
    enable_kube_prometheus_stack           = try(var.addons.enable_kube_prometheus_stack, false)
    enable_metrics_server                  = try(var.addons.enable_metrics_server, false)
    enable_prometheus_adapter              = try(var.addons.enable_prometheus_adapter, false)
    enable_secrets_store_csi_driver        = try(var.addons.enable_secrets_store_csi_driver, false)
    enable_vpa                             = try(var.addons.enable_vpa, false)
  }

  addons = merge(
    local.aws_addons,
    local.oss_addons,
    { kubernetes_version = local.cluster_version },
    { aws_cluster_name = module.eks.cluster_name }
  )

  #----------------------------------------------------------------
  # GitOps Bridge, define metadatas to pass from Terraform to ArgoCD
  #----------------------------------------------------------------

  addons_metadata = merge(
    try(module.eks_blueprints_addons.gitops_metadata, {}), # eks blueprints addons automatically expose metadatas
    try(module.eks_ack_addons.gitops_metadata, {}),        # eks blueprints ack addons automatically expose metadatas
    {
      aws_cluster_name = module.eks.cluster_name
      aws_region       = local.region
      aws_account_id   = data.aws_caller_identity.current.account_id
      aws_vpc_id       = data.aws_vpc.vpc.id
      cluster_endpoint = module.eks.cluster_endpoint
      env              = local.env
    },
    {
      argocd_password                             = bcrypt(data.aws_secretsmanager_secret_version.admin_password_version.secret_string)
      aws_secret_manager_git_private_ssh_key_name = local.aws_secret_manager_git_private_ssh_key_name

      gitops_workloads_url      = local.gitops_workloads_url
      gitops_workloads_path     = local.gitops_workloads_path
      gitops_workloads_revision = local.gitops_workloads_revision

      addons_repo_url      = local.gitops_addons_url
      addons_repo_basepath = local.gitops_addons_basepath
      addons_repo_path     = local.gitops_addons_path
      addons_repo_revision = local.gitops_addons_revision
    },
    {
      eks_cluster_domain  = local.eks_cluster_domain
      external_dns_policy = "sync"
      ingress_type        = local.ingress_type
      #argocd_route53_weight      = local.argocd_route53_weight
      #route53_weight             = local.route53_weight
      #ecsfrontend_route53_weight = local.ecsfrontend_route53_weight
      #aws_security_group_ingress_nginx = aws_security_group.ingress_nginx.id
      dns_private_domain              = "vpc-lattice-custom-domain.io"
      lattice_default_service_network = local.lattice_default_service_network
      ingress_nginx_service_type      = "ClusterIP"
      target_group_arn                = local.service == "blue" ? data.aws_lb_target_group.tg_blue.arn : data.aws_lb_target_group.tg_green.arn # <-- Add this line
      external_lb_dns                 = data.aws_lb.alb.dns_name
    }
  )

  #---------------------------------------------------------------
  # Manifests for bootstraping the cluster for addons & workloads
  #---------------------------------------------------------------

  argocd_apps = {
    addons    = file("${path.module}/../../bootstrap/addons.yaml")
    workloads = file("${path.module}/../../bootstrap/workloads.yaml")
    # addons = templatefile("${path.module}/../../bootstrap/addons.yaml.template", {
    #   repoURL        = local.gitops_addons_url
    #   path           = local.gitops_addons_path
    #   targetRevision = local.gitops_addons_revision
    # })
    # workloads = templatefile("${path.module}/../../bootstrap/workloads.yaml.template", {
    #   repoURL        = local.gitops_workloads_url
    #   path           = local.gitops_workloads_path
    #   targetRevision = local.gitops_workloads_revision
    # })
  }


  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/aws-ia/terraform-aws-eks-blueprints"
  }

}

################################################################################
# Datas for External Load Balancer
################################################################################
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

#END Local
