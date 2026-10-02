variable "bucket_name" {
  description = "バケット名（全世界で一意）"
  type        = string
}

variable "force_destroy" {
  description = "中身があっても削除できるようにするか（開発環境のみ true）"
  type        = bool
  default     = false
}
