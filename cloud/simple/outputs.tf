output "web_public_ip" {
  value = aws_instance.web.public_ip
}

output "web_instance_id" {
  description = "Session Manager での接続: aws ssm start-session --target <この値>"
  value       = aws_instance.web.id
}

output "db_endpoint" {
  value = aws_db_instance.db.address
}

output "db_master_user_secret_arn" {
  value = aws_db_instance.db.master_user_secret[0].secret_arn
}
