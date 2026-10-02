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
  description = "Aurora PostgreSQL の版（ローカルの PostgreSQL 16 とメジャー版をそろえる）"
  type        = string
  default     = "16.6"
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
  type    = bool
  default = true
}
