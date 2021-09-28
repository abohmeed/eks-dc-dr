variable "vpc_name" {
  type = string
}
variable "cluster_name" {
  type = string
}
variable "vpc_cidr_block" {
  type = string
}
variable "instance_type" {
  type = string
}
variable "region" {
  type = string
}
variable "vpc_id" {
  default = ""
}
variable "k8s_service_account_name" {
  type = string
}
variable "k8s_service_account_namespace" {
  type = string
}
variable "s3_bucket" {
  type = string
}
variable "min_nodes" {
  type = number
}
variable "max_nodes" {
  type = number
}
variable "desired_nodes" {
  type = number
}
variable "cluster_version" {}
variable "zoneid" {}
variable "externalDNS-enabled" {
  type = bool
}
variable "pod-s3-subjects" {
  type = list(string)
}