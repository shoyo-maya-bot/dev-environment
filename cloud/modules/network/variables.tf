variable "name" {
  description = "リソース名の接頭辞（例: sample-dev1）"
  type        = string
}

variable "cidr_block" {
  description = "VPC の CIDR"
  type        = string
  default     = "10.0.0.0/16"
}

variable "enable_nat_gateway" {
  description = "NAT ゲートウェイを作るか（費用がかかる）"
  type        = bool
  default     = true
}
