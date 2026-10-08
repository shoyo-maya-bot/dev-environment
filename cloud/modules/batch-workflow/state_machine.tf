# ジョブフローの定義（Amazon States Language）. main.tf の aws_sfn_state_machine が使う.
#
# バッチの終了コード（README の「サンプルアプリの決まりごと」）を見て、結果を分ける:
#   0         → Succeeded（成功）
#   4         → 警告あり. 通知して（create_notification_topic = true のとき）SucceededWithWarning（成功扱い）
#   それ以外  → 通知して（同上）JobFailed（失敗）. 8（異常終了）、終了コードが取れない（コンテナが起動しなかった）、ECS の起動失敗も含む
#
# ecs:runTask.sync は、コンテナが 0 以外で終わると States.TaskFailed で失敗し、Cause に（文字列にした）タスクの情報が入る.
# 0 で終わったときは、同じ形のタスクの情報が結果になる. どちらでも $.task に置き、Containers[0].ExitCode を Choice で見る.
#   - Cause が JSON でない・無いときは、終了コードが分からないので失敗にする（StringMatches は値が無いと実行時エラーになるので、先に IsPresent で確かめる）
#   - コンテナはタスク定義の 1 つ（app）だけなので Containers[0] で見る. サイドカーを足したら、app のものを選ぶように直す
#
# 時間の上限（止まったままのジョブを残さない）:
#   - RunJob の TimeoutSeconds = var.job_timeout_seconds. 超えると States.Timeout で失敗し、Catch（States.ALL）から失敗の通知 → JobFailed へ進む
#     （Step Functions は runTask.sync のタイムアウトで ECS タスクも止める）
#   - 通知（sns:publish）にも短い上限（notify_timeout_seconds）. 通知が詰まってもジョブの結果は変えない
#   - 状態機械全体の TimeoutSeconds は「RunJob の上限 + 起動の再試行の待ち + 通知 + 余裕」. RunJob の上限が必ず先に来るので、
#     時間切れは上の失敗の経路（通知あり）で終わる. 全体の上限は、それでも終わらなかったときの最後の歯止め
# 定義の検査: .github/scripts/test_batch_workflow.py（terraform console で値を取り出し、終了コードごとの行き先を確かめる. plan/apply はしない）
locals {
  # 終了コードの意味（sample-app の BatchJob.OK / WARN と同じ値）
  exit_code_ok   = 0
  exit_code_warn = 4

  notification_topic_name = "${var.name}-notification"
  # SNS トピックの ARN は名前から決まる（定義を作る時点で値が分かるので、terraform console で検査できる）
  notification_topic_arn = "arn:${local.partition}:sns:${local.region}:${local.account_id}:${local.notification_topic_name}"

  exit_code_path = "$.task.Containers[0].ExitCode"

  # 時間の上限（秒）
  notify_timeout_seconds = 60
  run_job_retry = {
    IntervalSeconds = 30
    MaxAttempts     = 2
    BackoffRate     = 2
  }
  # 起動の再試行の待ちの合計（30 + 60 秒）
  run_job_retry_wait_seconds = sum([
    for i in range(local.run_job_retry.MaxAttempts) : local.run_job_retry.IntervalSeconds * pow(local.run_job_retry.BackoffRate, i)
  ])
  # 起動の再試行・通知・状態の切り替えの余裕
  execution_margin_seconds = 600
  execution_timeout_seconds = (
    var.job_timeout_seconds + local.run_job_retry_wait_seconds + local.notify_timeout_seconds + local.execution_margin_seconds
  )

  base_states = {
    RunJob = {
      Type           = "Task"
      Resource       = "arn:aws:states:::ecs:runTask.sync"
      TimeoutSeconds = var.job_timeout_seconds
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
      ResultPath = "$.task"
      Retry      = [merge({ ErrorEquals = ["ECS.AmazonECSException"] }, local.run_job_retry)]
      Catch = [
        # コンテナが 0 以外で終わった（終了コードは Cause の中）
        { ErrorEquals = ["States.TaskFailed"], ResultPath = "$.error", Next = "HasFailureCause" },
        # ECS の起動失敗・権限不足・タイムアウト（States.Timeout. job_timeout_seconds を超えた）など（終了コードは無い）
        { ErrorEquals = ["States.ALL"], ResultPath = "$.error", Next = local.on_failure },
      ]
      Next = "CheckExitCode"
    }

    HasFailureCause = {
      Type    = "Choice"
      Choices = [{ Variable = "$.error.Cause", IsPresent = true, Next = "IsFailureCauseJson" }]
      Default = local.on_failure
    }

    IsFailureCauseJson = {
      Type    = "Choice"
      Choices = [{ Variable = "$.error.Cause", StringMatches = "{*", Next = "ParseFailureCause" }]
      Default = local.on_failure
    }

    ParseFailureCause = {
      Type       = "Pass"
      Parameters = { "value.$" = "States.StringToJson($.error.Cause)" }
      ResultPath = "$.parsed"
      Next       = "UseFailedTask"
    }

    # 失敗したタスクの情報を、成功したときと同じ $.task に置く
    UseFailedTask = {
      Type       = "Pass"
      InputPath  = "$.parsed.value"
      ResultPath = "$.task"
      Next       = "CheckExitCode"
    }

    CheckExitCode = {
      Type = "Choice"
      Choices = [
        { Not = { Variable = local.exit_code_path, IsPresent = true }, Next = local.on_failure },
        { Variable = local.exit_code_path, NumericEquals = local.exit_code_ok, Next = "Succeeded" },
        { Variable = local.exit_code_path, NumericEquals = local.exit_code_warn, Next = local.on_warning },
      ]
      Default = local.on_failure
    }

    Succeeded = { Type = "Succeed" }

    SucceededWithWarning = {
      Type    = "Succeed"
      Comment = "終了コード 4（形式エラーの行を飛ばして取込を続けた）. 成功扱い. 飛ばした行はアプリのログ（APPW0001）で確かめる"
    }

    JobFailed = {
      Type  = "Fail"
      Error = "JobFailed"
      Cause = "バッチが 0・4 以外の終了コードで終わったか、起動できないか、時間の上限を超えました（実行の入出力の task・error と CloudWatch Logs を確かめる）"
    }
  }

  # 通知の状態（create_notification_topic = true のときだけ）. 通知の失敗でジョブの結果を変えない（Catch して先に進む）
  notify_states = {
    NotifyWarning = {
      Type           = "Task"
      Resource       = "arn:aws:states:::sns:publish"
      TimeoutSeconds = local.notify_timeout_seconds
      Parameters = {
        TopicArn    = local.notification_topic_arn
        Subject     = "[${var.name}] WARNING: exit code ${local.exit_code_warn}"
        "Message.$" = "States.JsonToString($)"
      }
      ResultPath = null
      Catch      = [{ ErrorEquals = ["States.ALL"], ResultPath = "$.notify_error", Next = "SucceededWithWarning" }]
      Next       = "SucceededWithWarning"
    }

    NotifyFailure = {
      Type           = "Task"
      Resource       = "arn:aws:states:::sns:publish"
      TimeoutSeconds = local.notify_timeout_seconds
      Parameters = {
        TopicArn    = local.notification_topic_arn
        Subject     = "[${var.name}] FAILED"
        "Message.$" = "States.JsonToString($)"
      }
      ResultPath = null
      Catch      = [{ ErrorEquals = ["States.ALL"], ResultPath = "$.notify_error", Next = "JobFailed" }]
      Next       = "JobFailed"
    }
  }

  on_warning = var.create_notification_topic ? "NotifyWarning" : "SucceededWithWarning"
  on_failure = var.create_notification_topic ? "NotifyFailure" : "JobFailed"

  state_machine_definition = {
    Comment        = "JOB を ECS タスクとして実行し、終了コードで結果を分ける（0 成功 / 4 警告で成功扱い / それ以外・時間切れは失敗）"
    StartAt        = "RunJob"
    TimeoutSeconds = local.execution_timeout_seconds
    States         = merge(local.base_states, var.create_notification_topic ? local.notify_states : {})
  }
}
