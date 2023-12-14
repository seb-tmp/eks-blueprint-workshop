# # data "aws_grafana_workspace" "this" {
# #   workspace_id = var.managed_grafana_workspace_id
# # }

# # locals {
# #   region          = var.aws_region
# #   amg_ws_endpoint = "https://${data.aws_grafana_workspace.this.endpoint}"
# # }
# locals {
#   #region               = var.aws_region
#   #eks_cluster_endpoint = data.aws_eks_cluster.this.endpoint
#   create_new_workspace = var.managed_prometheus_workspace_id == "" ? true : false
# }

# # resource "grafana_folder" "this" {
# #   title = "Amazon Managed Prometheus monitoring dashboards"
# # }

# # module "managed_prometheus_monitoring" {
# #   source                           = "../../modules/managed-prometheus-monitoring"
# #   dashboards_folder_id             = resource.grafana_folder.this.id
# #   aws_region                       = local.region
# #   managed_prometheus_workspace_ids = var.managed_prometheus_workspace_ids
# #   condition = var.managed_grafana_workspace_id != ""
# # }

# # deploys the base module
# module "aws_observability_accelerator" {
#   source = "github.com/aws-observability/terraform-aws-observability-accelerator?ref=v2.9.2"
#   aws_region = var.aws_region
#   enable_managed_prometheus = "true" #local.create_new_workspace
#   managed_prometheus_workspace_id = var.managed_prometheus_workspace_id
#   enable_alertmanager = true
#   managed_grafana_workspace_id = var.managed_grafana_workspace_id

#   tags = local.tags
# }

# module "eks_monitoring" {
#   source = "github.com/aws-observability/terraform-aws-observability-accelerator//modules/eks-monitoring?ref=v2.9.2"

#   eks_cluster_id = module.eks.cluster_name

#   enable_amazon_eks_adot = true
#   enable_cert_manager = false
#   enable_apiserver_monitoring = true
#   enable_kube_state_metrics = false
#   enable_node_exporter = false
#   enable_tracing = false

#   # control the publishing of dashboards by specifying the boolean value for the variable 'enable_dashboards', default is 'true'
#   # This configuration section results in actions performed on AMG and AMP; and it needs to be done just once
#   # And hence, this in performed in conjunction with the setup of the eks_cluster_1 EKS cluster
#   enable_dashboards       = true
#   enable_external_secrets = false
#   enable_fluxcd           = false
#   enable_alerting_rules   = false
#   enable_recording_rules  = false

#   enable_grafana_operator = true
#   grafana_api_key         = var.grafana_api_key
#   target_secret_name      = "grafana-admin-credentials"
#   target_secret_namespace = "grafana-operator"
#   grafana_url             = module.aws_observability_accelerator.managed_grafana_workspace_endpoint

#   managed_prometheus_workspace_id = module.aws_observability_accelerator.managed_prometheus_workspace_id
#   managed_prometheus_workspace_endpoint = module.aws_observability_accelerator.managed_prometheus_workspace_endpoint
#   managed_prometheus_workspace_region   = module.aws_observability_accelerator.managed_prometheus_workspace_region

#   # optional, defaults to 60s interval and 15s timeout
#   prometheus_config = {
#     global_scrape_interval = "60s"
#     global_scrape_timeout  = "15s"
#     scrape_sample_limit    = 2000
#   }

#   #enable_logs = true

#   tags = local.tags

#   depends_on = [
#     module.aws_observability_accelerator
#   ]
# }

