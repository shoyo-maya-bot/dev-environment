terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  # 状態ファイルは S3 に保存し、DynamoDB でロックする（値は backend.hcl に書いて init 時に渡す）
  #   terraform init -backend-config=backend.hcl
  backend "s3" {}
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      System      = var.system_name
      Environment = "dev1"
      ManagedBy   = "terraform"
    }
  }
}
