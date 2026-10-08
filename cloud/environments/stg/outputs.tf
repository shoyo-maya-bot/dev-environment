output "db_endpoint" {
  value = module.db.endpoint
}

output "bucket_name" {
  value = module.bucket.bucket_name
}

output "async_queue_url" {
  value = module.async_queue.queue_url
}

output "job0001_state_machine_arn" {
  value = module.job0001.state_machine_arn
}

output "job0001_notification_topic_arn" {
  description = "JOB0001 の通知の SNS トピック（job0001_notification = false なら null）. 購読（メールなど）はここに付ける"
  value       = module.job0001.notification_topic_arn
}
