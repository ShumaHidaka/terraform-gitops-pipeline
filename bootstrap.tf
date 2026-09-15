provider "aws" {
  region = "ap-northeast-1"
}

# 1. tfstate管理用 S3バケット
resource "aws_s3_bucket" "tfstate" {
  bucket        = "shuma-terraform-tfstate-20260909"
  force_destroy = false

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# 2. 排他ロック用 DynamoDB
# resource "aws_dynamodb_table" "tfstate_lock" {
#   name         = "terraform-lock"
#   billing_mode = "PAY_PER_REQUEST"
#   hash_key     = "LockID"
#
#   attribute {
#     name = "LockID"
#     type = "S"
#   }
# }

# 3. OIDCプロバイダー設定 (GitHub Actions用)
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

# 4. GitHub Actions用 IAMロール
resource "aws_iam_role" "github_actions" {
  name = "github-actions-terraform-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.github.arn
        }
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:ShumaHidaka/terraform-gitops-pipeline:*"
          }
        }
      }
    ]
  })
}

# GitHub ActionsロールにAdministratorAccess権限を付与（検証用）
resource "aws_iam_role_policy_attachment" "github_actions_admin" {
  role       = aws_iam_role.github_actions.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# 出力（後でGitHubの設定に使用）
output "role_arn" {
  value       = aws_iam_role.github_actions.arn
  description = "GitHub Actionsに設定するIAM RoleのARN"
}
