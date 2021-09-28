#!/usr/bin/env bash
bucket=$1
if [[ -z $bucket ]]; then
  echo "Please enter the Terraform state bucket name"
  exit 1
fi
aws s3 ls s3://"${bucket}" 2>/dev/null || aws s3 mb s3://"${bucket}"