---
description: ローカル開発環境のエラーを調べて、原因と直し方を案内する
agent: agent
argument-hint: 出ているエラーメッセージ（そのまま貼り付け）
---

ローカル開発環境で次のエラーが出ています。

${input:error:エラーメッセージを貼り付け}

## 進め方

1. [local/README.md](../../local/README.md) の「よくあるつまずき」に当てはまるかを最初に確認する
2. 状況を確かめるコマンドを 1 つずつ提案し、結果を聞いてから次に進む（`docker compose ps`、`java -version`、`docker compose logs db` など）
3. 原因が分かったら、直し方を番号付きの手順で示す（Windows の PowerShell と Git Bash で違う場合は両方）
4. 直ったことを確かめる方法（どのコマンドで何が出れば OK か）を最後に示す

## してはいけないこと

- データを消すコマンド（`docker compose down -v` など）を、影響を説明せずに勧める
- 管理者権限が必要な操作を、その旨を伝えずに勧める
