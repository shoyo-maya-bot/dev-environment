# dev-environment

Java（Spring Boot + MyBatis）開発の **ローカル開発環境** と **クラウド開発環境（AWS + Terraform）** の雛形・手順書です。
「ローカルでロジックを開発・単体テストし、クラウドの共有環境で結合テスト・疎通確認する」二段構えで使います。

> 特定の企業・案件の構成の写しではなく、一般的な構成で作り直したものです。実案件では値と命名を自分たちの設計に合わせてください。

## 中身

| フォルダ | 内容 | はじめに読む |
|---|---|---|
| [local/](local/README.md) | Windows 11 での開発環境の作り方（WSL2・Rancher Desktop・Corretto・VS Code）、DB と S3 エミュレータの `docker-compose.yml` | ✅ 新しく参加した人はここから |
| [sample-app/](sample-app/) | 動作確認と教材用のサンプル（会員 API、注文ファイル取込バッチ、単体テスト、Karate の API テスト） | ローカル環境ができたら |
| [cloud/](cloud/README.md) | AWS の構成と Terraform（ECS Fargate・Aurora・S3・SQS・Step Functions）、簡易環境（EC2 + RDS） | クラウド環境を触る人 |

> 教材（learning-materials）の演習は、弱いところを直す前のコードを残した **`exercise-base` ブランチ** で解きます。`main` は修正済みです（`git diff exercise-base main -- sample-app` で直し方を比べられます）。

## 技術スタック

| 区分 | 採用 |
|---|---|
| 言語・FW | Java 17、Spring Boot 4.0、MyBatis（mybatis-spring-boot-starter 4.0） |
| ビルド | Gradle 8.14（Wrapper で固定） |
| テスト | JUnit 5、Mockito、AssertJ、Spring MockMvc、Karate（API テスト）、JaCoCo（カバレッジ） |
| ローカル | Rancher Desktop（dockerd）、PostgreSQL 16、S3 互換エミュレータ |
| クラウド | AWS（ECS Fargate、Aurora PostgreSQL、S3、SQS、Step Functions、EventBridge Scheduler、Secrets Manager）、Terraform |

## サンプルアプリの決まりごと（他のリポジトリと共通）

| 項目 | 形式 | 例 |
|---|---|---|
| パッケージ | `com.example.<アプリ名>` | `com.example.sample` |
| API ID / ジョブ ID | `API` + 4 桁 / `JOB` + 4 桁 | `API0001`、`JOB0001` |
| メッセージ ID | `APP` + 種別（I 情報 / W 警告 / E エラー）+ 4 桁 | `APPE0002` |
| バッチの終了コード | 0 正常 / 4 警告あり / 8 異常 | — |

実案件では、社内のパッケージ名・ID 体系・共通ライブラリに置き換えます。

## このリポジトリの CI

push と PR のたびに GitHub Actions で次を確認します（[.github/workflows/ci.yml](.github/workflows/ci.yml)）。

- サンプルアプリのビルドと単体テスト（Java 17）
- `local/docker-compose.yml` で DB と S3 エミュレータが healthy まで起動すること
- Terraform の書式（`terraform fmt`）と構文（`terraform validate`）

## 関連リポジトリ

- [ai-coding](https://github.com/shoyo-maya-bot/ai-coding): 設計書から AI でコードと単体テストを作る仕組み（このリポジトリの構成を前提にする）
- [learning-materials](https://github.com/shoyo-maya-bot/learning-materials): 新人向け教材（sample-app を教材に使う）
- [devtools-workspace](https://github.com/shoyo-maya-bot/devtools-workspace): ツール一覧と一括セットアップ
