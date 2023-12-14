variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "us-west-2"
}

variable "environment_name" {
  description = "The name of Environment Infrastructure stack name, feel free to rename it. Used for cluster and VPC names."
  type        = string
  default     = "eks-blueprint"
}

variable "ingress_type" {
  type        = string
  description = "Type of ingress to uses (alb | nginx | ...). this parameter will be sent to arocd via gitops bridge"
  default     = "alb"
}

variable "eks_admin_role_name" {
  type        = string
  description = "Additional IAM role to be admin in the cluster"
  default     = ""
}

variable "aws_secret_manager_git_private_ssh_key_name" {
  type        = string
  description = "Secret Manager secret name for hosting Github SSH-Key to Access private repository"
  default     = "github-blueprint-ssh-key"
}

variable "argocd_secret_manager_name_suffix" {
  type        = string
  description = "Name of secret manager secret for ArgoCD Admin UI Password"
  default     = "argocd-admin-secret"
}

variable "gitops_workloads_org" {
  type        = string
  description = "Git repository org/user contains for workloads"
  default     = "https://github.com/aws-samples"
}

variable "gitops_workloads_repo" {
  type        = string
  description = "Git repository contains for workloads"
  default     = "eks-blueprints-workloads"
}

variable "gitops_workloads_revision" {
  type        = string
  description = "Git repo revision in workload_repo_url for the ArgoCD workload deployment"
  default     = "main"
}

variable "gitops_workloads_path" {
  type        = string
  description = "Git repo path in workload_repo_url for the ArgoCD workload deployment"
  default     = "envs/dev"
}
variable "gitops_addons_org" {
  type        = string
  description = "Git repository org/user contains for addons"
  default     = "https://github.com/gitops-bridge-dev"
}
variable "gitops_addons_repo" {
  type        = string
  description = "Git repository contains for addons"
  default     = "gitops-bridge-argocd-control-plane-template"
}
variable "gitops_addons_basepath" {
  type        = string
  description = "Git repository base path for addons"
  default     = ""
}
variable "gitops_addons_path" {
  type        = string
  description = "Git repository path for addons"
  default     = "bootstrap/control-plane/addons"
}
variable "gitops_addons_revision" {
  type        = string
  description = "Git repository revision/branch/ref for addons"
  default     = "HEAD"
}

variable "managed_prometheus_workspace_id" {
  description = "Amazon Managed Service for Prometheus Workspace ID"
  type        = string
  default     = ""
}

variable "managed_grafana_workspace_id" {
  description = "Amazon Managed Grafana workspace ID"
  type        = string
  default     = ""
}

variable "grafana_api_key" {
  description = "API key for authorizing the Grafana provider to make changes to Amazon Managed Grafana"
  type        = string
  sensitive   = true
}

variable "addons" {
  description = "Kubernetes addons"
  type        = any
  default = {
    enable_cert_manager                          = true
    enable_aws_efs_csi_driver                    = false
    enable_aws_fsx_csi_driver                    = false
    enable_aws_cloudwatch_metrics                = true
    enable_aws_privateca_issuer                  = false
    enable_cluster_autoscaler                    = false
    enable_external_dns                          = false
    enable_external_secrets                      = true
    enable_aws_load_balancer_controller          = true
    enable_aws_for_fluentbit                     = true
    enable_aws_node_termination_handler          = false
    enable_karpenter                             = true
    enable_velero                                = false
    enable_aws_gateway_api_controller            = true
    enable_aws_ebs_csi_resources                 = true # generate gp2 and gp3 storage classes for ebs-csi
    enable_aws_secrets_store_csi_driver_provider = false
    enable_ack_apigatewayv2                      = false
    enable_ack_dynamodb                          = false
    enable_ack_s3                                = false
    enable_ack_rds                               = false
    enable_ack_prometheusservice                 = false
    enable_ack_emrcontainers                     = false
    enable_ack_sfn                               = false
    enable_ack_eventbridge                       = false
    enable_ack_iam                               = true
    enable_aws_argocd_ingress                    = false

    enable_argo_rollouts            = false
    enable_argo_workflows           = false
    enable_gpu_operator             = false
    enable_kube_prometheus_stack    = false
    enable_ingress_nginx            = true
    enable_kyverno                  = true
    enable_metrics_server           = true
    enable_prometheus_adapter       = false
    enable_secrets_store_csi_driver = false
    enable_vpa                      = false
    enable_foo                      = true # you can add any addon here, make sure to update the gitops repo with the corresponding application set
  }
}
