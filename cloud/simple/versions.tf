terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.67"
    }
  }
}

provider "aws" {
  region = var.region
  default_tags {
    tags = {
      System      = var.system_name
      Environment = "simple"
      ManagedBy   = "terraform"
    }
  }
}
