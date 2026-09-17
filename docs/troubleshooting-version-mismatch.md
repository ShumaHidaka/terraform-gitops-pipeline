# GitHub Actions × Terraform バージョン不整合エラー解決記録

## 1. 発生した問題
- **エラーメッセージ:** 
  `Error: Unsupported argument on backend.tf line 16, in terraform: 16: use_lockfile = true An argument named "use_lockfile" is not expected here.`
- **事象:** 
  OIDC 認証成功後の `Terraform Init` ステップにおいて、`backend.tf` 内の `use_lockfile = true` という記述が未サポート（`Unsupported argument`）となり、パイプラインが失敗した。

## 2. 根本原因
- **ローカルと GitHub Actions 間の Terraform バージョンの乖離:**
  - **ローカル環境:** `v1.15.8`（1.10.0 以上）が導入されていた。S3 バックエンドにおける排他制御の新機能（`use_lockfile`）が利用可能であったため、`backend.tf` に記述を追加していた。
  - **GitHub Actions 環境:** ワークフロー YAML（`terraform.yml`）側で `terraform_version: "1.5.0"` とピンポイントで固定されていた。
- **機能差によるエラー:**
  `use_lockfile` は Terraform 1.10.0 以降で導入された仕様のため、1.5.0 の環境で `init` を実行した際に引数が認識されずエラーとなった。

## 3. 解決策（修正内容）
ローカルの実行環境（`v1.15.8`）に合わせて、GitHub Actions 側の Terraform バージョンを引き上げて固定し、両環境の互換性を確保した。また、`backend.tf` 側の必要バージョン条件も引き上げた。

### 1. `.github/workflows/terraform.yml` の修正
Setup Terraform ステップの `terraform_version` を `1.15.8` へ引き上げ。

```yaml
- name: Setup Terraform
  uses: hashicorp/setup-terraform@v3
  with:
    terraform_version: "1.15.8"
```

### 2. `backend.tf` の修正
`required_version` を `">= 1.15.0"` へ修正し、古いバージョンでの意図しない実行を防御。

```yaml
terraform {
  required_version = ">= 1.15.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket       = "shuma-terraform-tfstate-20260909"
    key          = "bootstrap/terraform.tfstate"
    region       = "ap-northeast-1"
    use_lockfile = true
    encrypt      = true
  }
}
```

## 4. ナレッジ・ベストプラクティス
- **CI/CD 環境でのバージョン指定方針:**
  CI/CD 側での `>= 1.10.0` のような動的・範囲指定は、ある日突然最新版が自動採用されて事故に繋がるリスク（非決定性）があるため推奨されない。CI/CD パイプラインでは `1.15.8` のように**ピンポイントで完全固定**するのが基本。
- **ローカルと CI/CD の同調:**
  ローカルで新しい構文やオプション（`use_lockfile` 等）を追加した場合は、必ず CI/CD 側の指定バージョンも合わせて更新する。