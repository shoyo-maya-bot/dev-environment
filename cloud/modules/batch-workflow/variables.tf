variable "name" {
  description = "ジョブフロー名（例: sample-dev1-job0001）"
  type        = string
}

variable "cluster_arn" {
  type = string
}

variable "task_definition_arn" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "security_group_ids" {
  type = list(string)
}

variable "pass_role_arns" {
  description = "タスクに渡す IAM ロール（実行ロールとタスクロール）"
  type        = list(string)
}

variable "command" {
  description = "コンテナの起動引数（ジョブ ID・入力ファイルなど）"
  type        = list(string)
}

variable "schedule_expression" {
  description = "定刻起動（例: cron(0 2 * * ? *)）。null なら手動起動のみ"
  type        = string
  default     = null
}

variable "create_notification_topic" {
  description = "警告（終了コード 4）と失敗（4 以外の 0 以外など）を通知する SNS トピックを作るか。購読（メールなど）は別に付ける。既定は作らない（通知しない）"
  type        = bool
  default     = false
}

variable "job_timeout_seconds" {
  description = "ジョブ（ECS タスク）1 回の実行の上限（秒）. 超えたらタスクを止めて失敗（通知の対象）にする. 既定 3600（1 時間）. ジョブフロー全体の上限は、これに起動の再試行・通知の分を足した値になる"
  type        = number
  default     = 3600

  validation {
    condition     = var.job_timeout_seconds == floor(var.job_timeout_seconds) && var.job_timeout_seconds >= 60 && var.job_timeout_seconds <= 86400
    error_message = "job_timeout_seconds は 60〜86400（1 分〜24 時間）の整数で指定してください。"
  }
}
