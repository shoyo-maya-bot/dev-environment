output "state_machine_arn" {
  value = aws_sfn_state_machine.this.arn
}

output "notification_topic_arn" {
  description = "通知の SNS トピックの ARN（create_notification_topic = false なら null）"
  value       = var.create_notification_topic ? aws_sns_topic.notification[0].arn : null
}

output "state_machine_definition" {
  description = "ジョブフローの定義（Amazon States Language. 検査用. .github/scripts/test_batch_workflow.py が読む）"
  value       = local.state_machine_definition
}
