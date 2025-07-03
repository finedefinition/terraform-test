output "bucket_name" {
  description = "Name of the S3 bucket containing application files"
  value       = aws_s3_bucket.app_files.bucket
}

output "bucket_arn" {
  description = "ARN of the S3 bucket containing application files"
  value       = aws_s3_bucket.app_files.arn
}