output "bucket_name" {
  description = "Created bucket name"
  value       = google_storage_bucket.raw.name
}

output "bucket_url" {
  description = "Created bucket URL"
  value       = google_storage_bucket.raw.url
}
