variable "primary_region" {
  type = string
  default = "ap-south-1"
}
variable "secondary_region" {
  type = string
  default = "us-east-1"
}
variable "cluster_name_primary" {
  type = string
  default = "shmr-primary"
}
variable "cluster_name_secondary" {
  type = string
  default = "shmr-secondary"
}
variable "hosted_zone_id" {
  type = string
  description = "Existing Route 53 public hosted zone ID"
}
variable "domain_name" {
  type = string
  description = "A domain managed in the supplied hosted zone"
}
variable "app_fqdn" {
  type = string
  description = "Application hostname, e.g. app.example.com"
}
variable "image" {
  type = string
  description = "Container image URI available to both clusters"
}
variable "vpc_cidr_primary" {
  type = string
  default = "10.10.0.0/16"
}
variable "vpc_cidr_secondary" {
  type = string
  default = "10.20.0.0/16"
}
variable "node_instance_type" {
  type = string
  default = "t3.medium"
}
variable "desired_nodes" {
  type = number
  default = 2
}
variable "primary_lb_dns" {
  type = string
  description = "DNS name of primary regional LoadBalancer; supply after service is provisioned"
}
variable "secondary_lb_dns" {
  type = string
  description = "DNS name of secondary regional LoadBalancer; supply after service is provisioned"
}
variable "primary_lb_dimension" {
  type = string
  description = "CloudWatch ALB LoadBalancer dimension, e.g. app/name/id"
}
variable "primary_target_group_dimension" {
  type = string
  description = "CloudWatch target group dimension, e.g. targetgroup/name/id"
}
