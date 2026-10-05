#!/usr/bin/env bash
# CI 用の動作確認. local/ の DB・S3 エミュレータと、起動したサンプルアプリに実際に問い合わせて結果を確かめる.
#
#   e2e.sh start    <jar>        API を起動し、応答するまで待つ
#   e2e.sh api      main|exercise-base   API を curl で呼んで、ステータスとメッセージ ID を確かめる
#   e2e.sh batch    <jar> main|exercise-base   取込バッチを jar で動かし、終了コードとログを確かめる
#   e2e.sh db-down  <local のディレクトリ>  DB を止めた状態で、API が 503 + APPE0008 を返すことを確かめる（main のみ）
#   e2e.sh karate-check <dir>    Karate のテストが 1 件以上通ったことを確かめる
#   e2e.sh stop                  API を止める
#
# ログは $LOG_DIR（既定は $RUNNER_TEMP/e2e-logs）に残す. 失敗時は annotate-tail.sh で注釈に出す.
set -euo pipefail

LOG_DIR="${LOG_DIR:-${RUNNER_TEMP:-/tmp}/e2e-logs}"
mkdir -p "$LOG_DIR"
API="http://localhost:8080/api/v1/members"
PROFILE_LOCAL="--spring.profiles.active=local"

fail() { echo "::error::$*"; exit 1; }

# call <メソッド> <URL> [JSON 本文] → STATUS と BODY を設定する
call() {
  local method=$1 url=$2 data=${3:-}
  local out="$LOG_DIR/last-response.json"
  local args=(-s -o "$out" -w '%{http_code}' --max-time 90 -X "$method" "$url")
  if [ -n "$data" ]; then
    args+=(-H 'Content-Type: application/json' -d "$data")
  fi
  STATUS=$(curl "${args[@]}" || true)
  BODY=$(cat "$out" 2>/dev/null || true)
  echo "$method $url -> $STATUS $BODY"
}

# expect <期待するステータス> [本文に含まれるはずの文字列 ...]
expect() {
  local want=$1; shift
  [ "$STATUS" = "$want" ] || fail "ステータスが $want ではなく $STATUS でした: $BODY"
  local s
  for s in "$@"; do
    case "$BODY" in
      *"$s"*) ;;
      *) fail "応答に $s が含まれていません: $BODY" ;;
    esac
  done
}

cmd_start() {
  local jar=${1:?jar}
  nohup java -jar "$jar" "$PROFILE_LOCAL" > "$LOG_DIR/app.log" 2>&1 &
  echo $! > "$LOG_DIR/app.pid"
  for _ in $(seq 1 90); do
    if curl -sf -o /dev/null "$API/1"; then
      echo "API が応答しました"
      return 0
    fi
    if ! kill -0 "$(cat "$LOG_DIR/app.pid")" 2>/dev/null; then
      fail "API のプロセスが終了しました（app.log を参照）"
    fi
    sleep 2
  done
  fail "API が 180 秒以内に応答しませんでした"
}

# Karate の結果（JUnit XML）にテストが 1 件以上あり、失敗が無いことを確かめる（0 件で「成功」に見えるのを防ぐ）
cmd_karate_check() {
  local dir=${1:?test-results/karateTest のディレクトリ}
  local tests=0 failures=0 f t e r
  for f in "$dir"/*.xml; do
    [ -f "$f" ] || continue
    t=$(grep -o '<testsuite [^>]*' "$f" | sed -nE 's/.* tests="([0-9]+)".*/\1/p' | head -1)
    e=$(grep -o '<testsuite [^>]*' "$f" | sed -nE 's/.* failures="([0-9]+)".*/\1/p' | head -1)
    r=$(grep -o '<testsuite [^>]*' "$f" | sed -nE 's/.* errors="([0-9]+)".*/\1/p' | head -1)
    tests=$((tests + ${t:-0})); failures=$((failures + ${e:-0} + ${r:-0}))
  done
  [ "$tests" -gt 0 ] || fail "Karate のテストが 1 件も実行されていません（$dir）"
  [ "$failures" -eq 0 ] || fail "Karate のテストが $failures 件失敗しました"
  echo "::notice title=Karate::$tests 件のシナリオが通りました"
}

cmd_stop() {
  if [ -f "$LOG_DIR/app.pid" ]; then
    kill "$(cat "$LOG_DIR/app.pid")" 2>/dev/null || true
  fi
}

cmd_api() {
  local mode=${1:?mode}
  local email="ci-$(date +%s)-$RANDOM@example.com"

  # 初期データの会員 1（local/db/init/02_data.sql）
  call GET "$API/1";                expect 200 '"id":1' '"email"'
  # 登録 → 照会
  call POST "$API" "{\"name\":\"CI 会員\",\"email\":\"$email\"}"
  expect 201 "\"email\":\"$email\""
  local id
  id=$(sed -E 's/.*"id":([0-9]+).*/\1/' <<<"$BODY")
  call GET "$API/$id";              expect 200 "\"email\":\"$email\""
  # 同じメールアドレスは 409 + APPE0003
  call POST "$API" "{\"name\":\"CI 会員\",\"email\":\"$email\"}"
  expect 409 '"messageId":"APPE0003"'
  # 存在しない会員は 404 + APPE0002
  call GET "$API/999999999";        expect 404 '"messageId":"APPE0002"'
  # 入力チェック（必須・形式）は 400 + APPE0001
  call POST "$API" '{"name":"","email":"not-an-email"}'
  expect 400 '"messageId":"APPE0001"'

  if [ "$mode" = main ]; then
    # main で直したところ: 型違いも同じエラーの形（400 + APPE0001）
    call GET "$API/abc";            expect 400 '"messageId":"APPE0001"'
  else
    # exercise-base は演習のため、型違いが ErrorResponse の形で返らないまま（教材 30-04 の前提）
    call GET "$API/abc"
    [ "$STATUS" = 400 ] || fail "型違いのステータスが 400 ではなく $STATUS でした"
    case "$BODY" in
      *'"messageId"'*) fail "exercise-base で型違いが ErrorResponse の形になっています（教材の前提が崩れています）: $BODY" ;;
    esac
  fi
  echo "::notice title=API ($mode)::curl での確認が通りました"
}

# run_batch <名前> <jar> <引数...> → BATCH_EXIT を設定する
run_batch() {
  local name=$1 jar=$2; shift 2
  set +e
  java -jar "$jar" "$PROFILE_LOCAL,batch" "$@" > "$LOG_DIR/$name.log" 2>&1
  BATCH_EXIT=$?
  set -e
  echo "$name: 終了コード $BATCH_EXIT"
  grep -E 'APP[IWE][0-9]{4}' "$LOG_DIR/$name.log" || true
}

cmd_batch() {
  local jar=${1:?jar} mode=${2:?mode}
  local input=--input=s3://sample-bucket/orders.csv

  # 1 回目: 3 件取込、数量 0 の 1 行は形式エラーで飛ばす → 終了コード 4（教材 10-05 の期待値）
  run_batch batch-1 "$jar" --app.batch.job=JOB0001 "$input"
  [ "$BATCH_EXIT" = 4 ] || fail "1 回目の終了コードが 4 ではなく $BATCH_EXIT でした"
  grep -q 'imported=3 duplicated=0 errors=1' "$LOG_DIR/batch-1.log" || fail "1 回目の件数が想定と違います"

  # 2 回目: 同じファイルでも二重に入らない
  run_batch batch-2 "$jar" --app.batch.job=JOB0001 "$input"
  [ "$BATCH_EXIT" = 4 ] || fail "2 回目の終了コードが 4 ではなく $BATCH_EXIT でした"
  grep -q 'imported=0 duplicated=3 errors=1' "$LOG_DIR/batch-2.log" || fail "2 回目の件数が想定と違います"

  # 存在しないジョブ ID
  run_batch batch-unknown "$jar" --app.batch.job=JOB9999
  if [ "$mode" = main ]; then
    [ "$BATCH_EXIT" = 8 ] || fail "存在しないジョブ ID の終了コードが 8 ではなく $BATCH_EXIT でした"
    grep -q 'APPE0006' "$LOG_DIR/batch-unknown.log" || fail "APPE0006 のログがありません"
  else
    # exercise-base は演習のため 0 のまま（教材 30-13 の前提）
    [ "$BATCH_EXIT" = 0 ] || fail "exercise-base で存在しないジョブ ID の終了コードが 0 ではなく $BATCH_EXIT でした（教材の前提が崩れています）"
  fi
  echo "::notice title=Batch ($mode)::JOB0001 は 4 → 4、存在しないジョブ ID は $BATCH_EXIT"
}

cmd_db_down() {
  local compose_dir=${1:?local ディレクトリ}
  (cd "$compose_dir" && docker compose stop db)
  call GET "$API/1"
  expect 503 '"messageId":"APPE0008"'
  grep -q 'APPE0008' "$LOG_DIR/app.log" || fail "APPE0008 のログがありません"
  # DB が戻れば、API を再起動しなくても応答が戻る
  (cd "$compose_dir" && docker compose start db)
  for _ in $(seq 1 30); do
    call GET "$API/1"
    if [ "$STATUS" = 200 ]; then
      echo "::notice title=DB down::503 + APPE0008 を返し、DB を戻すと 200 に戻りました"
      return 0
    fi
    sleep 2
  done
  fail "DB を戻した後も API が 200 を返しませんでした"
}

sub=${1:?サブコマンドを指定してください}; shift
case "$sub" in
  start)   cmd_start "$@" ;;
  stop)    cmd_stop ;;
  api)     cmd_api "$@" ;;
  batch)   cmd_batch "$@" ;;
  db-down) cmd_db_down "$@" ;;
  karate-check) cmd_karate_check "$@" ;;
  *) fail "不明なサブコマンド: $sub" ;;
esac
