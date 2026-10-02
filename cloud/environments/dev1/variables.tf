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
  description = "アプリのコンテナイメージ（ECR の URI:タグ）。CI がビルドして push したものを指定する"
  type        = string
}

variable "bucket_name" {
  description = "入出力ファイル用バケット名（全世界で一意）"
  type        = string
}

variable "job0001_schedule" {
  description = "JOB0001 の定刻起動（null なら手動のみ）"
  type        = string
  default     = null
}
