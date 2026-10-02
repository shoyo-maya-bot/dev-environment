# 環境 prod の構成。環境ごとの違いは locals の値だけにする（構造は全環境で同じ）
locals {
  name               = "${var.system_name}-prod"
  enable_nat_gateway = true
  db_instance_count  = 2
  protect_data       = true
  api_desired_count  = 2
}

module "network" {
  source             = "../../modules/network"
  name               = local.name
  cidr_block         = var.vpc_cidr
  enable_nat_gateway = local.enable_nat_gateway
}

module "bucket" {
  source        = "../../modules/s3-bucket"
  bucket_name   = var.bucket_name
  force_destroy = !local.protect_data
}

module "async_queue" {
  source = "../../modules/sqs-queue"
  name   = "${local.name}-async"
}

resource "aws_ecs_cluster" "this" {
  name = local.name
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

data "aws_iam_policy_document" "app" {
  statement {
    actions   = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
    resources = [module.bucket.bucket_arn, "${module.bucket.bucket_arn}/*"]
  }
  statement {
    actions   = ["sqs:SendMessage", "sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
    resources = [module.async_queue.queue_arn]
  }
}

module "api" {
  source           = "../../modules/ecs-service"
  name             = "${local.name}-api"
  region           = var.region
  cluster_arn      = aws_ecs_cluster.this.arn
  vpc_id           = module.network.vpc_id
  subnet_ids       = module.network.private_subnet_ids
  image            = var.app_image
  container_port   = 8080
  desired_count    = local.api_desired_count
  task_policy_json = data.aws_iam_policy_document.app.json
  environment = {
    SPRING_PROFILES_ACTIVE = "cloud"
    DB_URL                 = "jdbc:postgresql://${module.db.endpoint}:5432/sampledb"
  }
  secrets = {
    DB_PASSWORD = "${module.db.master_user_secret_arn}:password::"
    DB_USER     = "${module.db.master_user_secret_arn}:username::"
  }
  secret_arns = [module.db.master_user_secret_arn]
}

module "batch" {
  source           = "../../modules/ecs-service"
  name             = "${local.name}-batch"
  region           = var.region
  cluster_arn      = aws_ecs_cluster.this.arn
  vpc_id           = module.network.vpc_id
  subnet_ids       = module.network.private_subnet_ids
  image            = var.app_image
  desired_count    = 0
  task_policy_json = data.aws_iam_policy_document.app.json
  environment = {
    SPRING_PROFILES_ACTIVE = "cloud,batch"
    DB_URL                 = "jdbc:postgresql://${module.db.endpoint}:5432/sampledb"
  }
  secrets = {
    DB_PASSWORD = "${module.db.master_user_secret_arn}:password::"
    DB_USER     = "${module.db.master_user_secret_arn}:username::"
  }
  secret_arns = [module.db.master_user_secret_arn]
}

module "db" {
  source                     = "../../modules/aurora-postgres"
  name                       = local.name
  vpc_id                     = module.network.vpc_id
  subnet_ids                 = module.network.private_subnet_ids
  allowed_security_group_ids = [module.api.security_group_id, module.batch.security_group_id]
  instance_count             = local.db_instance_count
  deletion_protection        = local.protect_data
}

module "job0001" {
  source              = "../../modules/batch-workflow"
  name                = "${local.name}-job0001"
  cluster_arn         = aws_ecs_cluster.this.arn
  task_definition_arn = module.batch.task_definition_arn
  subnet_ids          = module.network.private_subnet_ids
  security_group_ids  = [module.batch.security_group_id]
  pass_role_arns      = [module.batch.execution_role_arn, module.batch.task_role_arn]
  command             = ["--app.batch.job=JOB0001", "--input=s3://${var.bucket_name}/inbound/orders.csv"]
  schedule_expression = var.job0001_schedule
}
