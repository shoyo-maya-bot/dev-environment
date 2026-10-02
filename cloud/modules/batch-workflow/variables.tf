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
