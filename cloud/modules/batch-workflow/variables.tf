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
