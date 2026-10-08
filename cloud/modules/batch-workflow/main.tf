# バッチのジョブフロー: EventBridge Scheduler で定刻起動 → Step Functions → ECS タスク（終了を待つ）
data "aws_iam_policy_document" "sfn_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["states.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "sfn" {
  name               = "${var.name}-sfn"
  assume_role_policy = data.aws_iam_policy_document.sfn_assume.json
}

data "aws_iam_policy_document" "sfn" {
  statement {
    actions   = ["ecs:RunTask", "ecs:StopTask", "ecs:DescribeTasks"]
    resources = [local.task_definition_family_arn, local.task_arn_pattern]
  }
  statement {
    actions   = ["iam:PassRole"]
    resources = var.pass_role_arns
  }
  statement {
    actions   = ["events:PutTargets", "events:PutRule", "events:DescribeRule"]
    resources = [local.ecs_sync_rule_arn]
  }
}

resource "aws_iam_role_policy" "sfn" {
  name   = "run-ecs-task"
  role   = aws_iam_role.sfn.id
  policy = data.aws_iam_policy_document.sfn.json
}

resource "aws_sfn_state_machine" "this" {
  name       = var.name
  role_arn   = aws_iam_role.sfn.arn
  definition = jsonencode(local.state_machine_definition)
}

# 失敗・警告の通知（create_notification_topic = true のときだけ）. 購読（メール・Chatbot など）は利用者が付ける
resource "aws_sns_topic" "notification" {
  count             = var.create_notification_topic ? 1 : 0
  name              = local.notification_topic_name
  kms_master_key_id = "alias/aws/sns" # AWS 管理のキーで暗号化（S3・Aurora と同じく、カスタマー管理キーは使わない）
}

# AWS 管理のキー（alias/aws/sns）で暗号化したトピックへ発行するには、そのキーの利用権限が要る
data "aws_kms_alias" "sns" {
  count = var.create_notification_topic ? 1 : 0
  name  = "alias/aws/sns"
}

data "aws_iam_policy_document" "notify" {
  count = var.create_notification_topic ? 1 : 0
  statement {
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.notification[0].arn]
  }
  statement {
    actions   = ["kms:GenerateDataKey", "kms:Decrypt"]
    resources = [data.aws_kms_alias.sns[0].target_key_arn]
  }
}

resource "aws_iam_role_policy" "notify" {
  count  = var.create_notification_topic ? 1 : 0
  name   = "publish-notification"
  role   = aws_iam_role.sfn.id
  policy = data.aws_iam_policy_document.notify[0].json
}

data "aws_iam_policy_document" "scheduler_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "scheduler" {
  count              = var.schedule_expression == null ? 0 : 1
  name               = "${var.name}-scheduler"
  assume_role_policy = data.aws_iam_policy_document.scheduler_assume.json
}

resource "aws_iam_role_policy" "scheduler" {
  count = var.schedule_expression == null ? 0 : 1
  name  = "start-execution"
  role  = aws_iam_role.scheduler[0].id
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "states:StartExecution", Resource = aws_sfn_state_machine.this.arn }]
  })
}

resource "aws_scheduler_schedule" "this" {
  count                        = var.schedule_expression == null ? 0 : 1
  name                         = var.name
  schedule_expression          = var.schedule_expression
  schedule_expression_timezone = "Asia/Tokyo"
  flexible_time_window {
    mode = "OFF"
  }
  target {
    arn      = aws_sfn_state_machine.this.arn
    role_arn = aws_iam_role.scheduler[0].arn
  }
}
