module "eks_blueprints_addon" {
  source  = "aws-ia/eks-blueprints-addon/aws"
  version = "~> 1.0" #ensure to update this to the latest/desired version

  chart            = "kubernetes-event-exporter"
  chart_version    = "0.1.0"
  repository       = "https://resmoio.github.io/kubernetes-event-exporter"
  description      = "Export Kubernetes events to multiple destinations with routing and filtering"
  namespace        = "monitoring"
  create_namespace = true

  #https://github.com/resmoio/kubernetes-event-exporter/blob/master/charts/kubernetes-event-exporter/values.yaml
  values = [
    <<-EOT
      resources:
        requests:
          cpu: 100m
          memory: 128Mi
        limits:
          cpu: 500m
          memory: 512Mi
    EOT
  ]

}
