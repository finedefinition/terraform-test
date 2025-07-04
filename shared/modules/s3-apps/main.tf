# S3 bucket for application files
resource "aws_s3_bucket" "app_files" {
  bucket = "${var.project_name}-app-files-${var.environment}"

  tags = merge(var.default_tags, {
    Name = "${var.project_name}-app-files"
    Type = "ApplicationFiles"
  })
}

resource "aws_s3_bucket_versioning" "app_files" {
  bucket = aws_s3_bucket.app_files.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "app_files" {
  bucket = aws_s3_bucket.app_files.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "app_files" {
  bucket = aws_s3_bucket.app_files.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Upload application files
resource "aws_s3_object" "backend_app" {
  bucket = aws_s3_bucket.app_files.id
  key    = "backend/app.py"
  source = "${path.root}/../../applications/backend/app.py"
  etag   = filemd5("${path.root}/../../applications/backend/app.py")

  tags = var.default_tags
}

resource "aws_s3_object" "backend_requirements" {
  bucket = aws_s3_bucket.app_files.id
  key    = "backend/requirements.txt"
  source = "${path.root}/../../applications/backend/requirements.txt"
  etag   = filemd5("${path.root}/../../applications/backend/requirements.txt")

  tags = var.default_tags
}


resource "aws_s3_object" "frontend_html" {
  bucket = aws_s3_bucket.app_files.id
  key    = "frontend/index.html"
  source = "${path.root}/../../applications/frontend/public/index.html"
  etag   = filemd5("${path.root}/../../applications/frontend/public/index.html")

  tags = var.default_tags
}

resource "aws_s3_object" "docker_compose" {
  bucket = aws_s3_bucket.app_files.id
  key    = "docker-compose.yml"
  source = "${path.root}/../../configs/docker-compose.yml"
  etag   = filemd5("${path.root}/../../configs/docker-compose.yml")

  tags = var.default_tags
}

resource "aws_s3_object" "nginx_config" {
  bucket = aws_s3_bucket.app_files.id
  key    = "nginx.conf"
  source = "${path.root}/../../configs/nginx.conf"
  etag   = filemd5("${path.root}/../../configs/nginx.conf")

  tags = var.default_tags
}