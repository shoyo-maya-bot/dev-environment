# モジュールが使う Terraform と provider の版の下限（版の固定は各環境の versions.tf と .terraform.lock.hcl で行う）
terraform {
  required_version = ">= 1.6"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}
