variable "unique_name" {
  type = string
  default = ""
}

variable "admin_ip" {
  type = string
  default = ""
}

variable "admin_ip_additional" {
  type = string
  default = ""
}

variable "aws_region" {
  type = string
  default = "us-east-1"
}

variable "aws_instance_types" {
  type = list(string)
}

variable "vpc_id" {
  type = string
}

variable "igw_id" {
  type = string
}