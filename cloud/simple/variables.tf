variable "region" {
  type    = string
  default = "ap-northeast-1"
}

variable "system_name" {
  type    = string
  default = "sample-proto"
}

variable "allowed_http_cidrs" {
  description = "Web 画面（Nginx 80 番）へ接続を許可する IP 範囲（社内の出口 IP など）"
  type        = list(string)
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}
