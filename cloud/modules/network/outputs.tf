output "vpc_id" {
  value = aws_vpc.this.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "vpc_endpoint_ids" {
  description = "作った VPC エンドポイントの ID（サービス名 → ID）。enable_vpc_endpoints = false なら空"
  value = merge(
    { for k, v in aws_vpc_endpoint.interface : k => v.id },
    var.enable_vpc_endpoints ? { s3 = aws_vpc_endpoint.s3[0].id } : {}
  )
}
