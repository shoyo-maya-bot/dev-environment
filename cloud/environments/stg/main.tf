# 環境 stg の構成。環境ごとの違いは locals の値だけにする（構造は全環境で同じ）
locals {
  name                   = "${var.system_name}-stg"
  enable_nat_gateway     = true
  db_instance_count      = 1
  protect_data           = true
  skip_db_final_snapshot = false
  api_desired_count      = 1
  enable_vpc_endpoints   = false
}

# API・バッチが DB に接続する資格情報のシークレット. app_db_secret_arn を指定すれば、そのアプリ用ユーザー（権限を絞ったもの）を使う.
# 指定しなければ、これまでどおり Aurora のマスターユーザー（学習・試作用. 実案件では使わない。cloud/README.md の「アプリ用の DB ユーザー」）
locals {
  db_app_secret_arn = coalesce(var.app_db_secret_arn, module.db.master_user_secret_arn)
}

module "network" {
  source               = "../../modules/network"
  name                 = local.name
  cidr_block           = var.vpc_cidr
  enable_nat_gateway   = local.enable_nat_gateway
  enable_vpc_endpoints = local.enable_vpc_endpoints
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
    APP_S3_REGION          = var.region # S3Config の app.s3.region（S3 バケットと同じリージョン）
  }
  secrets = {
    DB_PASSWORD = "${local.db_app_secret_arn}:password::"
    DB_USER     = "${local.db_app_secret_arn}:username::"
  }
  secret_arns = [local.db_app_secret_arn]
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
    APP_S3_REGION          = var.region # S3Config の app.s3.region（S3 バケットと同じリージョン）
  }
  secrets = {
    DB_PASSWORD = "${local.db_app_secret_arn}:password::"
    DB_USER     = "${local.db_app_secret_arn}:username::"
  }
  secret_arns = [local.db_app_secret_arn]
}

module "db" {
  source                     = "../../modules/aurora-postgres"
  name                       = local.name
  vpc_id                     = module.network.vpc_id
  subnet_ids                 = module.network.private_subnet_ids
  allowed_security_group_ids = [module.api.security_group_id, module.batch.security_group_id]
  instance_count             = local.db_instance_count
  deletion_protection        = local.protect_data
  skip_final_snapshot        = local.skip_db_final_snapshot
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
  # 終了コード 4（警告）と失敗を SNS で通知する（true でトピックを作る. 購読は別に付ける）
  create_notification_topic = var.job0001_notification
}
