variable "region" {
  type    = string
  default = "ap-northeast-1"
}

variable "system_name" {
  description = "システム名（リソース名の接頭辞に使う）"
  type        = string
  default     = "sample"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "app_image" {
  description = "アプリのコンテナイメージ（ECR の URI:タグ）。ビルドと push はこのサンプルの範囲外（cloud/README.md）なので、別に用意したものを指定する"
  type        = string
}

variable "bucket_name" {
  description = "入出力ファイル用バケット名（全世界で一意）"
  type        = string
}

variable "job0001_notification" {
  description = "JOB0001 の警告（終了コード 4）と失敗を通知する SNS トピックを作るか（既定は作らない）"
  type        = bool
  default     = false
}

variable "job0001_schedule" {
  description = "JOB0001 の定刻起動（null なら手動のみ）"
  type        = string
  default     = null
}

variable "app_db_secret_arn" {
  description = "API・バッチが DB に接続するアプリ用ユーザーの Secrets Manager のシークレットの ARN（JSON の username・password を持つもの）。null なら Aurora のマスターユーザーで接続する（学習・試作用。cloud/README.md の「アプリ用の DB ユーザー」）"
  type        = string
  default     = null

  validation {
    condition     = var.app_db_secret_arn == null || can(regex("^arn:aws[a-z-]*:secretsmanager:[a-z0-9-]+:[0-9]{12}:secret:.+$", var.app_db_secret_arn))
    error_message = "app_db_secret_arn は Secrets Manager のシークレットの ARN（arn:aws:secretsmanager:<region>:<account>:secret:<name>）で指定してください。"
  }
}
