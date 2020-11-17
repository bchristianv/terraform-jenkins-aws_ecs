# Variable definitions

variable "aws_region" {
  type        = string
  description = "The AWS region in which to perform configuration operations"
  default     = "us-east-1"
}

variable "certificate_arn" {
  type        = string
  description = "ARN of an existing certificate which will be attached to the ALB"
}

variable "ecs-app_tags" {
  type        = map(string)
  description = "Tags to add to the ECS application service, task, and related resources"
  default     = {}
}

variable "ecs-cluster_name" {
  type        = string
  description = "The name of the ECS cluster"
}

variable "ecs-tags" {
  type        = map(string)
  description = "Tags to add to ECS cluster - 'Name' will be excluded"
  default     = {}
}

variable "jenkins_docker_image" {
  type        = string
  description = "Name of the Jenkins Docker image to use"
  default     = "jenkins/jenkins:lts"
}

variable "vpc-az_private_subnets" {
  type        = map(map(number))
  description = "Private subnets map of region AZ ID to subnet bits and network number, eg: {b = { sbits = 8, net = 1 }}"
  default     = {}
}

variable "vpc-az_public_subnets" {
  type        = map(map(number))
  description = "Public subnets map of region AZ ID to subnet bits and network number, eg: {a = { sbits = 8, net = 1 }}"
  default     = {}
}

variable "vpc-cidr" {
  type        = string
  description = "The IP block in CIDR notation for this VPC"
  validation {
    condition     = can(regex("((\\d{1,3})\\.){3}\\d{1,3}/\\d{1,2}", var.vpc-cidr))
    error_message = "The IP block must be valid CIDR notation."
  }
}

variable "vpc-internal_dns_domainname" {
  type        = string
  description = "The domain name for the Route53 internal hosted zone"
}

variable "vpc-name" {
  type        = string
  description = "The value to use for the VPC `Name` tag"
}

variable "vpc-tags" {
  type        = map(string)
  description = "Tags to add to VPC resources that support them - 'Name' may be excluded"
  default     = {}
}
