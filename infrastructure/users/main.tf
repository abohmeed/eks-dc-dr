provider "aws" {
  region = "eu-west-1"
}
terraform {
  required_version = ">= 0.13.1"
  backend "s3" {
    bucket = "ghostinfra-user-terraform-state"
    key    = "default.tfstate"
    region = "eu-west-1"
  }
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "user-policy" {
  statement {
    actions = ["sts:AssumeRole"]
    effect  = "Allow"
    principals {
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.id}:root"]
      type        = "AWS"
    }
  }
}
resource "aws_iam_role" "dev-role" {
  name               = "dev-role"
  assume_role_policy = data.aws_iam_policy_document.user-policy.json
}
resource "aws_iam_role" "sec-role" {
  name               = "sec-role"
  assume_role_policy = data.aws_iam_policy_document.user-policy.json
}
resource "aws_iam_group" "dev" {
  name = "dev"
}
resource "aws_iam_group" "sec" {
  name = "sec"
}
resource "aws_iam_group_policy" "dev" {
  name  = "dev"
  group = aws_iam_group.dev.name
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "AllowAssumeOrganizationAccountRole",
        "Effect" : "Allow",
        "Action" : "sts:AssumeRole",
        "Resource" : aws_iam_role.dev-role.arn
      }
    ]
    }
  )
}
resource "aws_iam_group_policy" "sec" {
  name  = "sec"
  group = aws_iam_group.sec.name
  policy = jsonencode({
    "Version" : "2012-10-17",
    "Statement" : [
      {
        "Sid" : "AllowAssumeOrganizationAccountRole",
        "Effect" : "Allow",
        "Action" : "sts:AssumeRole",
        "Resource" : aws_iam_role.sec-role.arn
      }
    ]
    }
  )
}
resource "aws_iam_user" "john" {
  name = "john"
}
resource "aws_iam_user" "jane" {
  name = "jane"
}
resource "aws_iam_group_membership" "dev" {
  name = "dev-group-membership"
  users = [
    aws_iam_user.john.name
  ]
  group = aws_iam_group.dev.name
}
resource "aws_iam_group_membership" "sec" {
  name = "sec-group-membership"
  users = [
    aws_iam_user.jane.name
  ]
  group = aws_iam_group.sec.name
}
resource "aws_iam_access_key" "john" {
  user = aws_iam_user.john.name
}
resource "aws_iam_access_key" "jane" {
  user = aws_iam_user.jane.name
}
output "dev-role" {
  value = aws_iam_role.dev-role.arn
}
output "sec-role" {
  value = aws_iam_role.sec-role.arn
}