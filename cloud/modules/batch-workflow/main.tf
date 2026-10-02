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
    resources = ["*"]
  }
  statement {
    actions   = ["iam:PassRole"]
    resources = var.pass_role_arns
  }
  statement {
    actions   = ["events:PutTargets", "events:PutRule", "events:DescribeRule"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "sfn" {
  name   = "run-ecs-task"
  role   = aws_iam_role.sfn.id
  policy = data.aws_iam_policy_document.sfn.json
}

resource "aws_sfn_state_machine" "this" {
  name     = var.name
  role_arn = aws_iam_role.sfn.arn
  definition = jsonencode({
    Comment = "JOB を ECS タスクとして実行し、終了を待つ"
    StartAt = "RunJob"
    States = {
      RunJob = {
        Type     = "Task"
        Resource = "arn:aws:states:::ecs:runTask.sync"
        Parameters = {
          LaunchType     = "FARGATE"
          Cluster        = var.cluster_arn
          TaskDefinition = var.task_definition_arn
          NetworkConfiguration = {
            AwsvpcConfiguration = {
              Subnets        = var.subnet_ids
              SecurityGroups = var.security_group_ids
              AssignPublicIp = "DISABLED"
            }
          }
          Overrides = {
            ContainerOverrides = [{
              Name    = "app"
              Command = var.command
            }]
          }
        }
        Retry = [{
          ErrorEquals     = ["ECS.AmazonECSException"]
          IntervalSeconds = 30
          MaxAttempts     = 2
          BackoffRate     = 2
        }]
        End = true
      }
    }
  })
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
