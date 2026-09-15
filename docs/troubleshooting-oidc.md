# GitHub Actions × AWS OIDC 認証エラー解決記録

## 1. 発生した問題
- **エラーメッセージ:** `Error: Could not assume role with OIDC: Not authorized to perform sts:AssumeRoleWithWebIdentity`
- **事象:** GitHub Actions の CI/CD パイプライン（`configure-aws-credentials` ステップ）実行時、AWS IAM ロールへの一時代理ログイン（OIDC ハンドシェイク）が失敗し拒否される。

## 2. 試したことと検証プロセス
1. **OIDC サムプリントの精査・修正:**
   - `bootstrap.tf` 内の `aws_iam_openid_connect_provider` において、旧証明書を含む複数指定から GitHub 推奨の最新サムプリント（`6938fd4d98bab03faadb97b34396831e3780aea1`）1つのみに絞り込み `terraform apply` を実施。
2. **Workflow 権限の確認:** 
   - `.github/workflows/` 内の YAML に `permissions: id-token: write` が最初から正しく付与されていることを確認。
3. **Secrets / Role ARN の整合性確認:** 
   - GitHub リポジトリの Secret に設定されている `AWS_ROLE_ARN` の値が、AWS 上の実物 IAM Role ARN と完全に一致していることを確認。
4. **AWS 側の実物リソース確認（AWS CLI）:** 
   - `aws iam get-open-id-connect-provider` および `aws iam get-role` を実行。
   - IAM Role 側の信頼関係設定が正しい構文で反映されていることを確認。
5. **JWT トークンデバッグステップの追加:**
   - 認証直前に curl / jq を使って GitHub Actions が実際に生成・送信している OIDC JWT トークンの Claim を可視化。

## 3. 根本原因
- **GitHub 側の「ID-based Subject Claims」仕様の適用:**
  GitHub Actions が発行した JWT トークンの `sub` クレームをデバッグ抽出した結果、以下の形式で値が送信されていたことが判明。
  `"sub": "repo:ShumaHidaka@184939877/terraform-gitops-pipeline@1361981740:pull_request"`
- **不一致の理由:**
  AWS IAM ロールの信頼ポリシー（Trust Policy）側で `repo:ShumaHidaka/terraform-gitops-pipeline:*` と指定していたため、GitHub が動的に埋め込んだアカウント ID（`@184939877`）およびリポジトリ ID（`@1361981740`）が含まれる実際の `sub` 文字列とマッチせず、AWS 側の認可判定で拒否されていた。

## 4. 解決策（修正内容）
IAM ロールの信頼ポリシー（`bootstrap.tf`）における `sub` 条件式のワイルドカード範囲を広げ、ID 挿入形式に対応するパターンへ修正した。

### `bootstrap.tf` 修正コード
```hcl
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
            # アカウント名・リポジトリ名直後に * を挿入し、@ID 形式の動的挿入に対応
            "token.actions.githubusercontent.com:sub" = "repo:ShumaHidaka*/terraform-gitops-pipeline*:*"
          }
        }
      }
    ]
  })
}