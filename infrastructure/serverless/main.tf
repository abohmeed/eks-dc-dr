resource "aws_iam_role" "iam_for_lambda" {
  name = "iam_for_lambda"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}
data "archive_file" "lambda_zip" {
  type        = "zip"
  output_path = "${path.module}/zips/payload.zip"
  source_dir  = "${path.module}/src"
}
resource "aws_lambda_function" "lambda" {
  filename      = "${path.module}/zips/payload.zip"
  function_name = "delete-lambda"
  role          = aws_iam_role.iam_for_lambda.arn
  handler       = "app.handler"
  runtime       = "nodejs14.x"
  environment {
    variables = {
      URL = ""
      KEY = ""
    }
  }
}