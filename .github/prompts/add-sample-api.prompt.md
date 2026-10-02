---
description: sample-app に API を 1 本追加する（コントローラ・サービス・Mapper・テスト・Karate）
agent: agent
argument-hint: 追加したい API（例「会員の一覧を名前の部分一致で検索する」）
---

`sample-app` に次の API を追加してください。

${input:api:例 GET /api/v1/members?name=山田 で部分一致検索}

## 手順

1. 設計を箇条書きで提案して確認をもらう: URL・メソッド・入力・出力・エラー（メッセージ ID）・SQL
2. 既存の `member` パッケージと同じ形で実装する（Controller → Service → Mapper + XML）
3. 単体テスト（Mapper を差し替えた Service のテスト、MockMvc の standalone テスト）を追加する
4. `src/test/resources/karate/` にシナリオを追加する
5. `./gradlew build` が通ることを確認して、作ったファイルと実行結果を報告する

## 守ること

- メッセージ ID は `common/MessageIds.java` と `messages.properties` に追加する
- SQL は Mapper XML に書く。文字列の連結で SQL を組み立てない（`#{}` を使う）
- テストを通すためにアサーションを消したり弱めたりしない
