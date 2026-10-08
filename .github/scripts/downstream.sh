#!/usr/bin/env bash
# dev-environment の変更が、写し先・引用先（公開リポジトリ）に与える影響を調べる（CI の downstream ジョブ）.
#
#   ai-coding          : scripts/check_template_drift.py（template/ と sample-app・local の差分）
#   learning-materials : scripts/check_code_quotes.py・check_versions.py（教材が引用したコードと版）
#
# どちらも dev-environment の決まった SHA に固定しているので、ここで差が出ても写し先がすぐ壊れるわけではない.
# 結果は参考情報（continue-on-error の扱い）. PR の base と head の両方で検査し、「この PR で新しく増えた指摘」だけを警告と Job Summary に出す（指摘があっても終了コードは 0. 取得の失敗など検査できなかったときだけ 1）.
# 増えた指摘は、写し先の SHA を上げるときに直す必要がある（直し方は各リポジトリの CONTRIBUTING / UPSTREAM.yaml）.
#
# 使い方: downstream.sh <base の SHA> <head の SHA>   （dev-environment の clone の中で実行. 対象の SHA は fetch 済みであること）
set -uo pipefail

base="$1"
head="$2"
repo_dir="$(git rev-parse --show-toplevel)"
work="${RUNNER_TEMP:-$(mktemp -d)}/downstream"
summary="${GITHUB_STEP_SUMMARY:-/dev/stdout}"
rm -rf "$work"
mkdir -p "$work"

clone() { # <name>
  git clone -q --depth 1 "https://github.com/shoyo-maya-bot/$1.git" "$work/$1" || exit 1
  echo "$1 @ $(git -C "$work/$1" rev-parse --short HEAD)"
}

# dev-environment の rev を、写し先のスクリプトが読める形で $work/up-<label> に用意する
# （別のリポジトリにする. worktree だと refs が元の clone と共有され、origin/main を書き換えてしまう）
prepare() { # <label> <rev>
  local dir="$work/up-$1"
  git init -q "$dir" || exit 1
  git -C "$dir" fetch -q --no-tags "$repo_dir" "$2" "refs/remotes/origin/exercise-base" || exit 1
  git -C "$dir" checkout -q --detach "$2" || exit 1
  # learning-materials の検査は origin/main・origin/exercise-base を読む
  git -C "$dir" update-ref refs/remotes/origin/main "$2"
  git -C "$dir" update-ref refs/remotes/origin/exercise-base "$(git -C "$repo_dir" rev-parse refs/remotes/origin/exercise-base)"
}

run_drift() { # <label>
  (cd "$work/ai-coding" && python scripts/check_template_drift.py --upstream-dir "$work/up-$1") >"$work/drift-$1.txt" 2>&1
  echo "drift[$1] exit=$?"
}

run_quotes() { # <label>
  local args=()
  # 固定の仕組み（dev-environment-pin.json）があれば、固定を外して作業中のコードと比べる
  if [ -f "$work/learning-materials/dev-environment-pin.json" ]; then
    args=(--ref main=HEAD --ref exercise-base=origin/exercise-base)
  fi
  {
    python "$work/learning-materials/scripts/check_code_quotes.py" --repo-dir "$work/up-$1" "${args[@]}"
    python "$work/learning-materials/scripts/check_versions.py" --repo-dir "$work/up-$1" "${args[@]}"
  } >"$work/quotes-$1.txt" 2>&1
  echo "quotes[$1] exit=$?"
}

# 指摘の行（ai-coding は "  - "、learning-materials は "NG " で始まる）のうち、head だけにあるもの
new_findings() { # <kind> <pattern>
  comm -13 <(grep -E "$2" "$work/$1-base.txt" | sort -u) <(grep -E "$2" "$work/$1-head.txt" | sort -u)
}

report() { # <title> <kind> <pattern> <how-to-fix>
  local found
  found="$(new_findings "$2" "$3")"
  {
    echo "### $1"
    if [ -z "$found" ]; then
      echo "この PR で増えた指摘はありません。"
    else
      echo "この PR で増えた指摘（写し先の固定 SHA を上げるときに対応が必要）:"
      echo '```'
      echo "$found"
      echo '```'
      echo "$4"
    fi
    echo "<details><summary>head での全出力</summary>"
    echo
    echo '```'
    tail -n 80 "$work/$2-head.txt"
    echo '```'
    echo "</details>"
    echo
  } >>"$summary"
  if [ -n "$found" ]; then
    while IFS= read -r line; do echo "::warning title=$1::$line"; done <<<"$found"
  fi
}

git -C "$repo_dir" fetch -q --no-tags origin "$base" "$head" "+refs/heads/exercise-base:refs/remotes/origin/exercise-base" || exit 1
clone ai-coding
clone learning-materials
python -m pip install -q "pyyaml==6.0.3" || exit 1 # ai-coding の constraints.txt と同じ版
prepare base "$base"
prepare head "$head"
for label in base head; do
  run_drift "$label"
  run_quotes "$label"
done

echo "## 写し先・引用先への影響（base ${base:0:7} → head ${head:0:7}）" >>"$summary"
# drift は 1 ファイルにつき最初の差だけを出すので、既にずれているファイルの変更は「増えた指摘」に出ない. 変えたファイルも並べる
changed="$(git -C "$repo_dir" diff --name-only "$base" "$head" -- sample-app local cloud)"
{
  echo "この PR で変えた、写し先・引用先が使うディレクトリ（sample-app/・local/・cloud/）のファイル:"
  echo '```'
  echo "${changed:-（なし）}"
  echo '```'
  echo
} >>"$summary"
report "ai-coding: template drift" drift '^  - ' \
  "ai-coding で \`python scripts/check_template_drift.py --ref main\` を実行し、template/ に取り込むか UPSTREAM.yaml に理由を書いてから sha を上げる。"
report "learning-materials: 引用と版" quotes '^NG ' \
  "learning-materials で \`python scripts/check_code_quotes.py --repo-dir ../dev-environment --ref main=HEAD\` を実行し、教材を直してから dev-environment-pin.json の SHA を上げる。"

exit 0
