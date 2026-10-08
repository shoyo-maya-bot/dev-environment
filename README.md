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
| 言語・FW | Java 17、Spring Boot 4.1、MyBatis（mybatis-spring-boot-starter 4.1） |
| ビルド | Gradle 9.8（Wrapper で固定。配布物の SHA-256 も照合） |
| テスト | JUnit 5、Mockito、AssertJ、Spring MockMvc、Karate（API テスト）、JaCoCo（カバレッジ） |
| ローカル | Rancher Desktop（dockerd）、PostgreSQL 16、S3 互換エミュレータ |
| クラウド | AWS（ECS Fargate、Aurora PostgreSQL、S3、SQS、Step Functions、EventBridge Scheduler、Secrets Manager）、Terraform |

版は `main` ブランチのもので、[sample-app/build.gradle](sample-app/build.gradle) と [gradle-wrapper.properties](sample-app/gradle/wrapper/gradle-wrapper.properties) が正です
（メジャー.マイナーまで書き、CI の `versions` ジョブがずれを検出します）。教材が使う `exercise-base` ブランチは版が古いことがあります。

## サンプルアプリの決まりごと（他のリポジトリと共通）

| 項目 | 形式 | 例 |
|---|---|---|
| パッケージ | `com.example.<アプリ名>` | `com.example.sample` |
| API ID / ジョブ ID | `API` + 4 桁 / `JOB` + 4 桁 | `API0001`、`JOB0001` |
| メッセージ ID | `APP` + 種別（I 情報 / W 警告 / E エラー）+ 4 桁 | `APPE0002` |
| バッチの終了コード | 0 正常 / 4 警告あり / 8 異常 | — |

実案件では、社内のパッケージ名・ID 体系・共通ライブラリに置き換えます。

## このリポジトリの CI

GitHub Actions で、ビルドが通るだけでなく、アプリが DB・S3 エミュレータとつながって実際に動くことまで確認します。
main への push と PR のたびに動き、イメージや依存の変化に気づけるよう週 1 回（月曜の朝）も動きます。

[ci.yml](.github/workflows/ci.yml)

| ジョブ | 確認すること |
|---|---|
| sample-app | ビルドと単体テスト（Java 17、`./gradlew build`）。Gradle Wrapper の jar が公式のものかも確かめる |
| windows | Windows（`windows-latest`）で `gradlew.bat build` が通ること、PowerShell スクリプトの構文（Windows PowerShell 5.1 で読めるか）と PSScriptAnalyzer |
| local-compose | `local/docker-compose.yml` の DB と S3 エミュレータが healthy まで起動し、初期データとサンプル CSV が置けること。`.env` でポートを変えてもスクリプトが追随すること、ポートが `127.0.0.1` だけで待ち受けること |
| e2e | local の DB・S3 エミュレータにつないでアプリを起動し、次を確かめる |
| terraform | Terraform の書式（`terraform fmt`）、構文（`terraform validate`。`.terraform.lock.hcl` どおりの provider で）、tflint、trivy config（IaC のセキュリティ検査。受け入れた指摘は [cloud/.trivyignore](cloud/.trivyignore) に理由付き） |
| windows-upload-sample | Windows で `local/scripts/upload-sample.ps1` を Windows PowerShell 5.1 と pwsh 7 で実際に実行する。送り先はジョブ内で起動した PUT だけを受け取るモック（[.github/scripts/s3_put_mock.py](.github/scripts/s3_put_mock.py)）で、AWS にはつながない。`.env` の `S3_PORT`・`S3_BUCKET` を読むこと、失敗時に終了コード 1 になること |
| env-parity | 環境（dev1 / stg / prod）の差が `main.tf` の `locals` の値と環境名だけであること（[.github/scripts/check_env_parity.py](.github/scripts/check_env_parity.py)） |
| downstream | PR のときだけ。この PR が写し先・引用先（ai-coding の template、learning-materials の教材）に与える影響を、公開リポジトリを clone して base と head で比べ、増えた指摘を警告と Job Summary に出す（[.github/scripts/downstream.sh](.github/scripts/downstream.sh)）。両者は dev-environment の SHA に固定しているので、マージは止めない（`continue-on-error`） |
| versions | README に書いた版（Java・Spring Boot・MyBatis・Gradle）がビルドファイルと一致すること（[.github/scripts/check_versions.py](.github/scripts/check_versions.py)。Windows でも実行）。スクリプトの bandit |

e2e で確かめること（[.github/scripts/e2e.sh](.github/scripts/e2e.sh)）:

- curl で API を呼び、照会 200・登録 201・重複 409（APPE0003）・存在しない会員 404（APPE0002）・入力誤り 400（APPE0001）が返る
- Karate の API テスト（`./gradlew karateTest`）が通る
- 取込バッチ JOB0001 が終了コード 4 で終わり、2 回目は二重に取り込まない。存在しないジョブ ID は終了コード 8（APPE0006）
- DB を止めると API が 503（APPE0008）を返し、DB を戻すと再起動なしで 200 に戻る

[exercise-base.yml](.github/workflows/exercise-base.yml)

教材が使う `exercise-base` ブランチを取り出して、教材の手順どおりに動くことを確かめます（main への push と週 1 回）。

- `./gradlew build` が通る
- API・Karate・取込バッチが、教材に書いた結果を返す
- 演習で見つけてもらう弱いところが残っている（型違いの 400 が `ErrorResponse` の形にならない、存在しないジョブ ID でも終了コード 0）。ここが落ちたら、`exercise-base` が変わって教材の前提が崩れています

Actions はコミットの SHA で固定しています（横にバージョンをコメントで書いています）。権限は読み取りだけで、チェックアウトした認証情報は残しません。

失敗したときは、ログの末尾が Actions の画面に注釈（エラー）として出ます。全体のログとテスト結果は、実行結果の Artifacts からダウンロードできます。

## 変更点

利用者の手順や動きが変わるものだけを書きます。

| 時期 | 変更 | 影響 |
|---|---|---|
| 2026-10 | `local/docker-compose.yml` の DB・S3 エミュレータを `127.0.0.1` だけで待ち受けるようにした | ほかの PC から、この PC の DB（5432）・S3 エミュレータ（9090）にはつながらなくなった（意図どおり） |
| 2026-10 | `local/scripts/upload-sample.*` が `local/.env` の `S3_PORT`・`S3_BUCKET` を読むようにした | `.env` でポートを変えた人は、環境変数を別に渡さなくてよくなった（環境変数があればそちらが優先） |
| 2026-10 | `cloud/` の dev1 に VPC エンドポイントを追加し、Step Functions の IAM の対象を ARN に絞った。`.terraform.lock.hcl` をコミット | dev1 を apply すると、エンドポイントの費用（月 約 100 USD の目安）がかかる。provider の版はロックファイルどおりになる |

## 関連リポジトリ

- [ai-coding](https://github.com/shoyo-maya-bot/ai-coding): 設計書から AI でコードと単体テストを作る仕組み（このリポジトリの構成を前提にする）
- [learning-materials](https://github.com/shoyo-maya-bot/learning-materials): 新人向け教材（sample-app を教材に使う）
- [devtools-workspace](https://github.com/shoyo-maya-bot/devtools-workspace): ツール一覧と一括セットアップ

## セキュリティ・ライセンス

- 脆弱性を見つけたら、公開の Issue ではなく [SECURITY.md](SECURITY.md) の方法で知らせてください
- ライセンスは [MIT](LICENSE) です
