output "aws_account_id" {
  description = "IAM AWS account id"
  value       = data.aws_caller_identity.current.account_id
}
output "cluster_oidc_issuer_url" {
  value = module.eks.cluster_oidc_issuer_url
}
output "kubectl_config" {
  value = module.eks.kubeconfig
}
output "vpc_id" {
  value = aws_vpc.main.id
}
output "private_subnets" {
  value = [aws_subnet.private01.id, aws_subnet.private02.id]
}
output "oidc_arn" {
  value = module.eks.oidc_provider_arn
}
output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}
output "cluster_ca_cert" {
  value = module.eks.cluster_certificate_authority_data
}
output "pods3_role_arn" {
  value = aws_iam_role.pods3.arn
}