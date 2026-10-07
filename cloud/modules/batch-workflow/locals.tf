# IAM の対象を絞るための ARN（main.tf の sfn ポリシーで使う）
#   cluster_arn は arn:aws:ecs:<リージョン>:<アカウント>:cluster/<名前> の形なので、そこからリージョンなどを取り出す.
locals {
  cluster_arn_parts = split(":", var.cluster_arn)
  partition         = local.cluster_arn_parts[1]
  region            = local.cluster_arn_parts[3]
  account_id        = local.cluster_arn_parts[4]
  cluster_name      = trimprefix(local.cluster_arn_parts[5], "cluster/")

  # ecs:RunTask の対象: このジョブのタスク定義（リビジョンは問わない。Terraform で更新しても権限を直さずに済む）
  task_definition_family_arn = "${replace(var.task_definition_arn, "/:[0-9]+$/", "")}:*"

  # ecs:StopTask・ecs:DescribeTasks の対象: このクラスターのタスク
  task_arn_pattern = "arn:${local.partition}:ecs:${local.region}:${local.account_id}:task/${local.cluster_name}/*"

  # ecs:runTask.sync（終了を待つ）で Step Functions が使う、AWS 管理の EventBridge ルール
  ecs_sync_rule_arn = "arn:${local.partition}:events:${local.region}:${local.account_id}:rule/StepFunctionsGetEventsForECSTaskRule"
}
