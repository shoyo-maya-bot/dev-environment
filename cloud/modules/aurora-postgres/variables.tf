variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "allowed_security_group_ids" {
  description = "DB への接続を許可するセキュリティグループ（アプリ側）"
  type        = list(string)
  default     = []
}

variable "engine_version" {
  description = "Aurora PostgreSQL の版（ローカルの PostgreSQL 16 とメジャー版をそろえる）. マイナー版が自動で上がったら、ここも実際の版に上げる（cloud/README.md の「DB の版」）"
  type        = string
  default     = "16.6"
}

variable "auto_minor_version_upgrade" {
  description = "メンテナンスウィンドウでマイナー版を自動で上げるか（DB インスタンスの設定. 既定 true は AWS の既定と同じ）"
  type        = bool
  default     = true
}

variable "database_name" {
  type    = string
  default = "sampledb"
}

variable "master_username" {
  type    = string
  default = "app_admin"
}

variable "instance_class" {
  type    = string
  default = "db.t4g.medium"
}

variable "instance_count" {
  description = "インスタンス数（本番は 2 以上で冗長化）"
  type        = number
  default     = 1
}

variable "backup_retention_days" {
  type    = number
  default = 7
}

variable "deletion_protection" {
  description = "クラスターの削除保護（true の間は destroy できない）。最終スナップショットは skip_final_snapshot で別に決める"
  type        = bool
  default     = true
}

variable "skip_final_snapshot" {
  description = "削除（destroy）のときに最終スナップショット（<name>-final）を取らない。既定は false（取る）。消えてよい学習・試作用の環境だけ true にする"
  type        = bool
  default     = false
}
