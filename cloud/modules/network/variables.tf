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

variable "enable_vpc_endpoints" {
  description = "private サブネットから AWS のサービス（ECR・S3・Secrets Manager・CloudWatch Logs・SQS）に届く VPC エンドポイントを作るか（NAT を置かない環境で使う。インターフェース型は費用がかかる）"
  type        = bool
  default     = false
}

variable "interface_endpoint_services" {
  description = "インターフェース型で作るエンドポイントのサービス名（com.amazonaws.<リージョン>. の後ろ）"
  type        = list(string)
  default     = ["ecr.api", "ecr.dkr", "secretsmanager", "logs", "sqs"]
}
