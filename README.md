# S3 + CloudFront 自動デプロイ CI/CD パイプライン構成書

本リポジトリは、Terraformによるインフラコード化（IaC）とGitHub ActionsによるCI/CDを用いて、S3 + CloudFront上の静的Webサイトを自動デプロイする仕組みを構築したものです。

---

## 1. システム全体構成・開発フロー

### 構成図

```text
[ 開発者（ローカル） ]
        │
        │ ① コード変更・作業ブランチへPush
        ▼
[ GitHub リポジトリ ]
        │
        │ ② Pull Request作成
        ▼
[ GitHub Actions ]
        │
        ├─ terraform fmt -check
        ├─ terraform validate
        └─ terraform plan
                │
                ▼
        [ PR上でPlan結果を確認 ]
                │
                │ ③ レビュー・承認・Merge
                ▼
[ GitHub Actions ]
        │
        ├─ terraform apply
        ├─ aws s3 sync
        └─ CloudFrontキャッシュ削除
                │
                ▼
[ AWS環境 ]
        ├── S3
        └── CloudFront
                │
                ▼
        [ Webユーザー（HTTPS） ]
```

### 初回構築時

初回のみ、Terraformの状態管理先となるS3バックエンドを先に用意する必要があります。

```text
backend設定を一時的に無効化
        ↓
TerraformでS3等を作成
        ↓
backend設定を有効化
        ↓
terraform init
        ↓
以降、tfstateをS3で管理
```

`tfstate`はS3上で管理し、S3のState Lock機能を利用してTerraformの同時実行による状態ファイルの競合を防止します。

---

## 2. 主な採用技術・コンポーネント

| コンポーネント | 採用技術・サービス | 役割・機能 |
| :--- | :--- | :--- |
| **IaC** | Terraform | AWSリソースのコード管理および`tfstate`管理 |
| **CI/CD** | GitHub Actions | `plan`・`apply`、S3同期、CloudFrontキャッシュ削除を自動実行 |
| **Web資産ストレージ** | Amazon S3 | `index.html`などの静的ファイルを保管 |
| **CDN** | Amazon CloudFront | HTTPS配信およびキャッシュ管理 |
| **アクセス制御** | CloudFront OAC | CloudFrontからS3へのアクセスのみを許可 |
| **状態管理** | Amazon S3 | Terraformの`tfstate`をリモート管理・Lock |

---

## 3. CI/CDの処理フロー

### Pull Request作成・更新時

GitHub Actionsにより、以下を自動実行します。

1. `terraform fmt -check`
2. `terraform validate`
3. `terraform plan`
4. `plan`結果をPull Request上で確認

Plan内容を確認し、問題がなければレビュー・承認後に`main`へMergeします。

### mainへのMerge時

MergeをトリガーとしてGitHub Actionsが以下を自動実行します。

1. `terraform apply -auto-approve`によるAWSリソース更新
2. `aws s3 sync`によるWeb資産のS3反映
3. `aws cloudfront create-invalidation`によるキャッシュ削除

これにより、**「変更 → PR → Plan確認 → Merge → AWS反映」**の流れを統一します。

---

## 4. GitHubとAWSの認証・セキュリティ

### OIDC認証

GitHub ActionsからAWSへのアクセスにはOIDC（OpenID Connect）を利用します。

```text
[ GitHub Actions ]
        │
        │ OIDC
        ▼
[ AWS IAM OIDC Provider ]
        │
        │ IAM Roleを引き受け
        ▼
[ AWS IAM Role ]
        │
        ▼
[ AWSリソース ]
```

長期的なAWS Access Key / Secret KeyをGitHubに保存せず、GitHub ActionsがOIDCを利用してAWS IAM Roleを一時的に引き受ける方式です。

GitHub側では、AWSのIAM Role ARNを設定し、AWS側では信頼するGitHubリポジトリやブランチ等を条件として設定します。

### S3 / CloudFrontのセキュリティ

- S3バケットはパブリックアクセスをブロック
- CloudFront OACを利用し、CloudFront経由でS3へアクセス
- S3バケットポリシーで対象CloudFrontディストリビューションからのアクセスを許可

---

## 5. Terraform `tfstate` の管理

Terraformの状態管理ファイル（`tfstate`）はローカルPCではなくS3で管理します。

これにより、複数人で同じTerraform環境を扱う場合でも状態を共有できます。

また、S3のState Lockを利用することで、複数のTerraform処理が同時に状態を更新することを防止します。

### 初回のみ

バックエンドとして使用するS3がまだ存在しないため、

1. backend設定を一時的にコメントアウト
2. Terraformで必要なS3等を作成
3. backend設定を有効化
4. `terraform init`を実行

という手順で初期設定を行います。

※現在のTerraformでは、S3バックエンドのネイティブなState Lockを`use_lockfile = true`で利用できます。DynamoDBによるLockは従来方式として残っていますが、現在は非推奨です。

---

## 6. ディレクトリ構成

```text
.
├── .github/
│   └── workflows/
│       └── terraform.yml       # GitHub Actions ワークフロー定義（CI/CD）
├── backend.tf                  # Terraform バックエンド設定（S3 / State Lock）
├── main.tf                     # プロバイダー定義および基本設定
├── cloudfront_s3.tf            # 静的Webサイト用インフラ定義（S3 / CloudFront / OAC）
├── index.html                  # Webサイトコンテンツ資産
└── README.md                   # 本ドキュメント（構成書）
```

---

## 7. セキュリティ設計のポイント

1. **OIDC認証**
   - GitHub ActionsからAWSへのアクセスに長期的なAWSアクセスキーを使用せず、一時的なIAM Roleを利用

2. **S3バケットの非公開化**
   - S3へのパブリックアクセスをブロックし、インターネットからの直接アクセスを制限

3. **OACによるアクセス制御**
   - CloudFrontからS3へのアクセスのみを許可

4. **`tfstate`のリモート管理**
   - Terraformの状態ファイルをS3で管理し、State Lockによって同時実行による競合を防止
