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
