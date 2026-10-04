# ローカル開発環境 セットアップ手順（Windows 11）

個人 PC で **ロジックの開発と単体テスト** を行う環境です。DB と S3 はコンテナのエミュレータで代替し、
ローカルからクラウドには接続しません。結合テスト・疎通確認はクラウドの開発環境（[../cloud/](../cloud/README.md)）で行います。

所要時間の目安: 初回 2〜3 時間（ダウンロード時間を含む）。各手順の「確認」が通ってから次へ進んでください。

## 0. 全体像

| 区分 | ツール | 版 | 役割 |
|---|---|---|---|
| OS 機能 | WSL2 | 最新 | コンテナを動かす Linux 環境 |
| コンテナ | Rancher Desktop（dockerd） | 最新 | `docker` / `docker compose` を使う（Docker Desktop の有償条件を避けられる） |
| Java | Amazon Corretto | 17（本番と同じ） | ビルド・実行。21 を入れていても 17 向けにコンパイルされる |
| ビルド | Gradle | Wrapper で 8.14.3 に固定 | 個別のインストール不要（`gradlew` が取得） |
| エディタ | VS Code + 拡張（Extension Pack for Java、Spring Boot Extension Pack、GitHub Copilot Chat） | 最新 | 開発 |
| Git | Git for Windows（Git Bash 付き） | 最新 | ソース管理。シェルスクリプトは Git Bash で動かす |
| DB | PostgreSQL 16（コンテナ） | 16 | クラウドの Aurora PostgreSQL の代わり |
| S3 | S3 互換エミュレータ（コンテナ） | `.env` で指定 | クラウドの S3 の代わり |
| （任意）AWS CLI | v2 | 最新 | クラウド環境を操作するときだけ |

## 1. WSL2 を有効にする

管理者権限の PowerShell で:

```powershell
wsl --install --no-distribution
```

PC を再起動します。

**確認**: `wsl --status` で「既定のバージョン: 2」と出る。
**うまくいかないとき**: BIOS で仮想化（Intel VT-x / AMD-V）が無効だと失敗します。社用 PC で変更できない場合は情報システム部門に相談してください。

## 2. Rancher Desktop を入れる

1. [Rancher Desktop](https://rancherdesktop.io/) のインストーラーを実行する
2. 初回起動の設定で **Container Engine を「dockerd (moby)」** にする（`docker` コマンドを使うため）
3. Kubernetes は使わないので無効にしてよい（メモリの節約）
4. Preferences → Virtual Machine でメモリを 4GB 以上にする

**確認**（PowerShell）: `docker version` と `docker compose version` が版を表示する。
**うまくいかないとき**: Rancher Desktop を起動した状態で、新しい PowerShell を開き直します。
`docker` が `failed to connect to the backend: timed out dialing Hyper-V socket` になる場合は（起動直後から、または数分後）、12 章の表を見てください（1.23.1 / 1.24.0 の不具合）。社内プロキシがある場合は Preferences → WSL → Network（または環境変数 `HTTPS_PROXY`）を設定します。

## 3. Java（Amazon Corretto 17）を入れる

1. [Amazon Corretto 17](https://docs.aws.amazon.com/corretto/latest/corretto-17-ug/downloads-list.html) の Windows x64 用 .msi を実行する
2. 環境変数 `JAVA_HOME` がインストール先（例: `C:\Program Files\Amazon Corretto\jdk17.x.x_x`）になっていることを確認する

**確認**: `java -version` が `17.` で始まる。

## 4. Git と VS Code

1. [Git for Windows](https://git-scm.com/download/win) をインストール（改行コードは既定の「Checkout Windows-style, commit Unix-style」でよい。このリポジトリは `.gitattributes` で改行を固定済み）
2. 初期設定（Git Bash）:

   ```bash
   git config --global user.name "<あなたの名前>"
   git config --global user.email "<あなたのメールアドレス>"
   ```

3. [VS Code](https://code.visualstudio.com/) をインストールし、拡張機能「Extension Pack for Java」「Spring Boot Extension Pack」「GitHub Copilot Chat」を入れる

**確認**: `git --version`、`code --version` が版を表示する。

## 5. このリポジトリを取得する

```bash
git clone https://github.com/shoyo-maya-bot/dev-environment.git
cd dev-environment
```

## 6. DB と S3 エミュレータを起動する

```bash
cd local
cp .env.example .env            # Windows の PowerShell なら: Copy-Item .env.example .env
docker compose up -d --wait     # 両方が healthy になるまで待つ
```

**確認**: `docker compose ps` で `db` と `s3` が `healthy`。
初期データ（会員 2 件）は初回起動時に `db/init/*.sql` で入ります。作り直したいときは `docker compose down -v` してから再度 `up`。

## 7. サンプルアプリを動かす（API）

```bash
cd ../sample-app
./gradlew bootRun --args='--spring.profiles.active=local'     # PowerShell は .\gradlew.bat
```

別のターミナルで:

```bash
curl http://localhost:8080/api/v1/members/1
curl -X POST http://localhost:8080/api/v1/members -H 'Content-Type: application/json' \
     -d '{"name":"新規 会員","email":"new@example.com"}'
```

**確認**: 1 つ目は会員 1 の JSON、2 つ目は `201` と採番された ID が返る。

## 8. サンプルバッチを動かす（注文ファイル取込 JOB0001）

```bash
cd ../local && ./scripts/upload-sample.sh        # PowerShell: .\scripts\upload-sample.ps1
cd ../sample-app
./gradlew bootRun --args='--spring.profiles.active=local,batch --app.batch.job=JOB0001 --input=s3://sample-bucket/orders.csv'
```

**確認**: ログに `APPI0002 JOB0001 終了 imported=3 duplicated=0 errors=1` と出る（4 行目は数量 0 のため飛ばす）。
もう一度実行すると `imported=0 duplicated=3` になる（再実行しても重複しない）。終了コードは 0 正常 / 4 形式エラーの行あり / 8 異常終了。

> サンプルの CSV には形式エラーの行がわざと 1 行あるため、バッチは終了コード 4 で終わります。`gradlew bootRun` は 0 以外を失敗として扱うので、
> 最後に `BUILD FAILED` と `finished with non-zero exit value 4` が出ますが、**上の `APPI0002` の行が出ていれば正常です**。

## 9. テスト

```bash
./gradlew test          # 単体テスト（DB・S3 不要）。カバレッジは build/reports/jacoco/test/html/index.html
./gradlew karateTest    # API テスト（7 の API を起動した状態で）。結果は build/karate-reports/
```

## 10. 日常の開発フロー

| タイミング | コマンド |
|---|---|
| 始業時 | Rancher Desktop を起動 → `cd local && docker compose up -d --wait` → `git pull` |
| 実装中 | `./gradlew test`（こまめに）、API は `bootRun` で確認 |
| push 前 | `./gradlew build`（コンパイル + 単体テスト）、API を変えたら `karateTest` |
| 終業時 | `docker compose stop`（データは残る） |

## 11. コマンド早見表

| やりたいこと | コマンド |
|---|---|
| ミドルウェア起動 / 停止 | `docker compose up -d --wait` / `docker compose stop` |
| データを消して作り直す | `docker compose down -v && docker compose up -d --wait` |
| DB に入る | `docker compose exec db psql -U app -d sampledb` |
| ログを見る | `docker compose logs -f db` |
| API 起動 | `./gradlew bootRun --args='--spring.profiles.active=local'` |
| バッチ起動 | `./gradlew bootRun --args='--spring.profiles.active=local,batch --app.batch.job=JOB0001 --input=<場所>'` |
| ビルド（jar） | `./gradlew bootJar` → `build/libs/sample-app-0.1.0.jar` |
| 単体テスト / API テスト | `./gradlew test` / `./gradlew karateTest` |

## 12. よくあるつまずき

| 症状 | 原因 | 対処 |
|---|---|---|
| `docker: command not found` | Rancher Desktop が起動していない、または containerd を選んでいる | 起動して Container Engine を dockerd にし、ターミナルを開き直す |
| `port is already allocated` | 5432 / 9090 / 8080 を別のソフトが使っている | `.env` の `DB_PORT` / `S3_PORT` を変える（アプリ側は `DB_URL` / `S3_ENDPOINT` も合わせる） |
| `./gradlew` が証明書エラー | 社内プロキシの SSL 検査 | 社内の CA 証明書を Java の cacerts に取り込む（情報システム部門の手順に従う） |
| `Connection refused`（DB） | コンテナが起動していない / healthy 前に接続した | `docker compose ps` で healthy を確認 |
| ログの日本語が文字化けする | Java 17 は Windows の既定の文字コード（MS932）でログを出す。`chcp 65001` にすると逆に化ける | `chcp` は既定（932）のまま起動する。ログをファイルに保存したときは Shift_JIS（MS932）で開く |
| `docker` が `timed out dialing Hyper-V socket` になる（起動直後から、または数分後） | Rancher Desktop 1.23.1 / 1.24.0 の不具合（docker の死活確認の URL を新しい curl が拒否する。[#10780](https://github.com/rancher-sandbox/rancher-desktop/issues/10780)） | devtools-workspace の `install-prereqs.cmd` を実行する（回避策を置く）か、下の「回避策」を手で置いて Rancher Desktop を再起動する |
| `upload-sample.ps1` が「Security Warning: Script Execution Risk」で止まる | 古い版のスクリプト（`-UseBasicParsing` なし） | `git pull` で最新にする。止まったときは `Y` で進めてよい |
| `gradlew: Permission denied`（Git Bash） | 実行権限が落ちた | `git update-index --chmod=+x gradlew` か `bash gradlew ...` |

### 回避策: Rancher Desktop の docker がつながらない・数分で止まる（1.23.1 / 1.24.0）

`%LOCALAPPDATA%\rancher-desktop\provisioning\fix-docker-healthcheck.start` を次の内容（改行は LF）で作り、Rancher Desktop を再起動します。
修正版の Rancher Desktop が出たら、このファイルは消してかまいません。

```sh
#!/bin/sh
sed -i 's|http://\./_ping|http://localhost/_ping|g' /etc/init.d/docker
```

**確認**: Rancher Desktop の起動から 3 分以上たっても `docker info` が成功する。
