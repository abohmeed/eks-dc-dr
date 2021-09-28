provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1alpha1"
      args        = ["eks", "get-token", "--cluster-name", var.cluster_name]
      command     = "aws"
    }
  }
}
resource "helm_release" "autosacler" {
  name      = "cluster-autoscaler"
  chart     = "https://github.com/kubernetes/autoscaler/releases/download/cluster-autoscaler-chart-9.10.7/cluster-autoscaler-9.10.7.tgz"
  namespace = "kube-system"
  set {
    name  = "awsRegion"
    value = var.region
  }
  set {
    name  = "rbac.create"
    value = "true"
  }
  set {
    name  = "rbac.serviceAccount.name"
    value = "cluster-autoscaler-aws-cluster-autoscaler-chart"
  }
  set {
    name  = "rbac.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.iam_assumable_role_admin.this_iam_role_arn
  }
  set {
    name  = "autoDiscovery.clusterName"
    value = var.cluster_name
  }
  set {
    name  = "autoDiscovery.enabled"
    value = "true"
  }
  depends_on = [module.eks]
}
resource "kubernetes_service_account" "aws-load-balancer-controller" {
  metadata {
    name      = "aws-load-balancer-controller"
    namespace = "kube-system"
    labels = {
      "app.kubernetes.io/component" = "controller"
      "app.kubernetes.io/name"      = "aws-load-balancer-controller"
    }
    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.AmazonEKSLoadBalancerControllerRole.arn
    }
  }
  depends_on = [module.eks]
}
# Although Terraform offers a Kustomize provisioner, it doesn't work with remote URLs. Using a local exec provisioner instead
######## kubectl MUST BE INSTALLED on machine where this shall run #################
resource "null_resource" "kubectl-crds" {
  provisioner "local-exec" {
    command = "echo \"$KUBECONFIG\" > /tmp/cluster && kubectl --kubeconfig=/tmp/cluster apply -k \"github.com/aws/eks-charts/stable/aws-load-balancer-controller/crds?ref=master\""
    environment = {
      KUBECONFIG = module.eks.kubeconfig
    }
  }
  depends_on = [module.eks]
}
resource "helm_release" "aws-load-balancer-controller" {
  name      = "aws-load-balancer-controller"
  chart     = "https://aws.github.io/eks-charts/aws-load-balancer-controller-1.2.7.tgz"
  namespace = "kube-system"
  set {
    name  = "clusterName"
    value = var.cluster_name
  }
  set {
    name  = "serviceAccount.create"
    value = "false"
  }
  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }
  depends_on = [module.eks]
}
################# Settings for ExternalDNS #####################
module "external_dns" {
  source                           = "git::https://github.com/DNXLabs/terraform-aws-eks-external-dns.git"
  cluster_name                     = var.cluster_name
  cluster_identity_oidc_issuer     = module.eks.cluster_oidc_issuer_url
  cluster_identity_oidc_issuer_arn = module.eks.oidc_provider_arn
  settings = {
    "policy" = "sync"
  }
  enabled = var.externalDNS-enabled
  depends_on = [module.eks]
}