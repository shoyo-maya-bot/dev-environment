variable "name" {
  type = string
}

variable "region" {
  type = string
}

variable "cluster_arn" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "image" {
  description = "コンテナイメージ（ECR の URI:タグ）"
  type        = string
}

variable "cpu" {
  type    = number
  default = 512
}

variable "memory" {
  type    = number
  default = 1024
}

variable "container_port" {
  description = "待ち受けポート（バッチは null）"
  type        = number
  default     = null
}

variable "desired_count" {
  description = "常駐させるタスク数（バッチは 0 = サービスを作らない）"
  type        = number
  default     = 0
}

variable "environment" {
  description = "環境変数（秘密情報は入れない）"
  type        = map(string)
  default     = {}
}

variable "secrets" {
  description = "環境変数名 → Secrets Manager / パラメータストアの ARN"
  type        = map(string)
  default     = {}
}

variable "secret_arns" {
  description = "読み出しを許可するシークレットの ARN"
  type        = list(string)
  default     = []
}

variable "task_policy_json" {
  description = "アプリに与える IAM ポリシー（JSON）。不要なら null"
  type        = string
  default     = null
}

variable "log_retention_days" {
  type    = number
  default = 30
}
