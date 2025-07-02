variable "project_name" {
  description = "Name of the project"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where security groups will be created"
  type        = string
}

variable "admin_cidr" {
  description = "CIDR block for admin SSH access"
  type        = string
  default     = "0.0.0.0/0"  # Ограничить в production!
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}


variable "default_tags" {
  description = "Default tags to apply to all resources"
  type        = map(string)
  default     = {}
}