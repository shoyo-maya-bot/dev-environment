# VPC エンドポイント（NAT ゲートウェイを置かない環境で、private サブネットの ECS タスクが AWS のサービスに届くようにする）
#   ECS Fargate（プラットフォーム 1.4 以降）がタスクを起動するには、次の経路が要る:
#     - ECR（api・dkr）: イメージの情報と本体の取得
#     - S3（ゲートウェイ型）: ECR のイメージの層は S3 に置かれている。アプリの入出力ファイルにも使う
#     - Secrets Manager: タスク定義の secrets（DB のパスワード）の読み出し
#     - CloudWatch Logs: awslogs ドライバーのログ出力
#   さらにアプリが使うもの:
#     - SQS: 非同期処理のキュー（タスクロールに権限がある）
#   Step Functions と EventBridge Scheduler は AWS 側から ECS を呼ぶので、タスクからの経路は要らない.
#
# インターフェース型は「1 つ × AZ の数」だけ時間課金される（ゲートウェイ型の S3 は無料）。費用の目安は cloud/README.md.

locals {
  interface_endpoint_services = var.enable_vpc_endpoints ? toset(var.interface_endpoint_services) : toset([])
}

data "aws_region" "current" {}

resource "aws_security_group" "endpoints" {
  count       = var.enable_vpc_endpoints ? 1 : 0
  name        = "${var.name}-vpce"
  description = "VPC interface endpoints (HTTPS from inside the VPC)"
  vpc_id      = aws_vpc.this.id
  tags        = { Name = "${var.name}-vpce" }
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_https" {
  count             = var.enable_vpc_endpoints ? 1 : 0
  security_group_id = aws_security_group.endpoints[0].id
  description       = "HTTPS from the VPC"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = var.cidr_block
}

resource "aws_vpc_endpoint" "interface" {
  for_each            = local.interface_endpoint_services
  vpc_id              = aws_vpc.this.id
  service_name        = "com.amazonaws.${data.aws_region.current.region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.endpoints[0].id]
  private_dns_enabled = true
  tags                = { Name = "${var.name}-vpce-${each.value}" }
}

resource "aws_vpc_endpoint" "s3" {
  count             = var.enable_vpc_endpoints ? 1 : 0
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]
  tags              = { Name = "${var.name}-vpce-s3" }
}
