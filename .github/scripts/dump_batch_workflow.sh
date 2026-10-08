#!/usr/bin/env bash
# cloud/modules/batch-workflow の状態機械の定義（JSON）を、通知なし・ありの 2 通り取り出す（CI の terraform ジョブ）.
# terraform console で module の output を評価するだけで、AWS にはつながない（plan / apply はしない）.
#
# 使い方: dump_batch_workflow.sh <出力先のフォルダ>
#   → <出力先>/definition-notify-false.json・definition-notify-true.json
#   → python .github/scripts/test_batch_workflow.py がこれを読んで、終了コードごとの行き先を確かめる
set -euo pipefail

out="$(mkdir -p "$1" && cd "$1" && pwd)"
repo="$(cd "$(dirname "$0")/../.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# hashicorp/setup-terraform は terraform を Node のラッパーで包む（標準入力を渡す console が止まる）. 本体（terraform-bin）があればそれを使う
tf=terraform
if [ -n "${TERRAFORM_CLI_PATH:-}" ] && [ -x "$TERRAFORM_CLI_PATH/terraform-bin" ]; then
  tf="$TERRAFORM_CLI_PATH/terraform-bin"
fi

# provider の版は dev1 のロックファイルどおり（-lockfile=readonly）
cp "$repo/cloud/environments/dev1/.terraform.lock.hcl" "$work/"
for notify in false true; do
  cat >"$work/main.tf" <<HCL
terraform {
  required_providers {
    aws = { source = "hashicorp/aws" }
  }
}

provider "aws" {
  region                      = "ap-northeast-1"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

module "job" {
  source                    = "$repo/cloud/modules/batch-workflow"
  name                      = "test-job0001"
  cluster_arn               = "arn:aws:ecs:ap-northeast-1:123456789012:cluster/test"
  task_definition_arn       = "arn:aws:ecs:ap-northeast-1:123456789012:task-definition/test-batch:3"
  subnet_ids                = ["subnet-a", "subnet-c"]
  security_group_ids        = ["sg-batch"]
  pass_role_arns            = ["arn:aws:iam::123456789012:role/exec", "arn:aws:iam::123456789012:role/task"]
  command                   = ["--app.batch.job=JOB0001", "--input=s3://bucket/inbound/orders.csv"]
  create_notification_topic = $notify
}
HCL
  timeout 300 "$tf" -chdir="$work" init -backend=false -input=false -lockfile=readonly >/dev/null
  echo 'jsonencode(module.job.state_machine_definition)' |
    AWS_EC2_METADATA_DISABLED=true timeout 120 "$tf" -chdir="$work" console |
    python3 -c 'import json, sys; json.dump(json.loads(json.loads(sys.stdin.read())), sys.stdout, ensure_ascii=False, indent=2)' \
      >"$out/definition-notify-$notify.json"
  echo "wrote $out/definition-notify-$notify.json"
done
