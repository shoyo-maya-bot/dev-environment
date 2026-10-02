variable "name" {
  type = string
}

variable "visibility_timeout_seconds" {
  description = "処理中のメッセージを他から見えなくする時間（処理時間より長く）"
  type        = number
  default     = 300
}

variable "max_receive_count" {
  description = "この回数失敗したらデッドレターキューへ"
  type        = number
  default     = 5
}
