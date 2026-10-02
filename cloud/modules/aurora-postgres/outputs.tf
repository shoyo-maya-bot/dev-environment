output "endpoint" {
  value = aws_rds_cluster.this.endpoint
}

output "master_user_secret_arn" {
  description = "マスターパスワードを格納した Secrets Manager の ARN"
  value       = aws_rds_cluster.this.master_user_secret[0].secret_arn
}

output "security_group_id" {
  value = aws_security_group.this.id
}
