provider "aws" {
  region = "eu-west-2"
}
terraform {
  required_version = ">= 0.13.1"
  backend "s3" {
    bucket = "ghostinfra-dr-terraform-state"
    key    = "default.tfstate"
    region = "eu-west-2"
  }
}
locals {
  cluster_name                  = "ghost-dr"
  cluster_version               = "1.21"
  instance_type                 = "t3.medium"
  vpc_name                      = "ghost"
  min_nodes                     = 1
  max_nodes                     = 4
  desired_nodes                 = 1
  region                        = "eu-west-2"
  k8s_service_account_namespace = "kube-system"
  k8s_service_account_name      = "cluster-autoscaler-aws-cluster-autoscaler-chart"
  vpc_cidr_block                = "192.168.0.0/16"
  pod-s3-subjects               = ["system:serviceaccount:default:pods3", "system:serviceaccount:dev:pods3"]
  domain                        = "dev.fakharany.com"
  zoneid                        = "Z09194512XJVWGHJ6A32M"
  assets-bucket                 = "assets.fakharany.com"
  externalDNS-enabled           = false
}

module "kubernetes" {
  source                        = "../irsa"
  region                        = local.region
  vpc_name                      = local.vpc_name
  cluster_name                  = local.cluster_name
  vpc_cidr_block                = local.vpc_cidr_block
  instance_type                 = local.instance_type
  k8s_service_account_name      = local.k8s_service_account_name
  k8s_service_account_namespace = local.k8s_service_account_namespace
  pod-s3-subjects               = local.pod-s3-subjects
  s3_bucket                     = local.assets-bucket
  cluster_version               = local.cluster_version
  max_nodes                     = local.max_nodes
  min_nodes                     = local.min_nodes
  desired_nodes                 = local.desired_nodes
  zoneid                        = local.zoneid
  externalDNS-enabled           = local.externalDNS-enabled
}
module "acm" {
  source              = "terraform-aws-modules/acm/aws"
  version             = "~> 3.0"
  domain_name         = local.domain
  zone_id             = local.zoneid
  wait_for_validation = true
  subject_alternative_names = [
    "*.${local.domain}"
  ]
}
output "acm_certificate_arn" {
  description = "The ARN of the certificate"
  value       = module.acm.acm_certificate_arn
}
resource "null_resource" "kubeconfig" {
  # Always export the KUBECONFIG
  triggers = {
    always_run = timestamp()
  }
  provisioner "local-exec" {
    command = "echo \"$KUBEOUT\" > $CLUSTERNAME && chmod 600 $CLUSTERNAME"
    environment = {
      KUBEOUT     = module.kubernetes.kubectl_config
      CLUSTERNAME = local.cluster_name
    }
  }
}
output "pods3_role_arn" {
  value = module.kubernetes.pods3_role_arn
}