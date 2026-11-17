data "aws_availability_zones" "primary" { provider = aws.primary, state = "available" }
data "aws_availability_zones" "secondary" { provider = aws.secondary, state = "available" }

module "primary_vpc" {
  source = "terraform-aws-modules/vpc/aws"
  version = "5.8.1"
  providers = { aws = aws.primary }
  name = "shmr-primary-vpc"
  cidr = var.vpc_cidr_primary
  azs = slice(data.aws_availability_zones.primary.names, 0, 2)
  private_subnets = [cidrsubnet(var.vpc_cidr_primary, 4, 1), cidrsubnet(var.vpc_cidr_primary, 4, 2)]
  public_subnets  = [cidrsubnet(var.vpc_cidr_primary, 4, 3), cidrsubnet(var.vpc_cidr_primary, 4, 4)]
  enable_nat_gateway = true
  single_nat_gateway = true
  enable_dns_hostnames = true
  enable_dns_support = true
  public_subnet_tags = { "kubernetes.io/role/elb" = "1" }
  private_subnet_tags = { "kubernetes.io/role/internal-elb" = "1" }
}
module "secondary_vpc" {
  source = "terraform-aws-modules/vpc/aws"
  version = "5.8.1"
  providers = { aws = aws.secondary }
  name = "shmr-secondary-vpc"
  cidr = var.vpc_cidr_secondary
  azs = slice(data.aws_availability_zones.secondary.names, 0, 2)
  private_subnets = [cidrsubnet(var.vpc_cidr_secondary, 4, 1), cidrsubnet(var.vpc_cidr_secondary, 4, 2)]
  public_subnets  = [cidrsubnet(var.vpc_cidr_secondary, 4, 3), cidrsubnet(var.vpc_cidr_secondary, 4, 4)]
  enable_nat_gateway = true
  single_nat_gateway = true
  enable_dns_hostnames = true
  enable_dns_support = true
  public_subnet_tags = { "kubernetes.io/role/elb" = "1" }
  private_subnet_tags = { "kubernetes.io/role/internal-elb" = "1" }
}

module "eks_primary" {
  source = "terraform-aws-modules/eks/aws"
  version = "20.8.5"
  providers = { aws = aws.primary }
  cluster_name = var.cluster_name_primary
  cluster_version = "1.29"
  cluster_endpoint_public_access = true
  vpc_id = module.primary_vpc.vpc_id
  subnet_ids = module.primary_vpc.private_subnets
  eks_managed_node_groups = {
    default = {
      instance_types = [var.node_instance_type]
      min_size = 1
      max_size = 3
      desired_size = var.desired_nodes
    }
  }
}
module "eks_secondary" {
  source = "terraform-aws-modules/eks/aws"
  version = "20.8.5"
  providers = { aws = aws.secondary }
  cluster_name = var.cluster_name_secondary
  cluster_version = "1.29"
  cluster_endpoint_public_access = true
  vpc_id = module.secondary_vpc.vpc_id
  subnet_ids = module.secondary_vpc.private_subnets
  eks_managed_node_groups = {
    default = {
      instance_types = [var.node_instance_type]
      min_size = 1
      max_size = 3
      desired_size = var.desired_nodes
    }
  }
}

# Expose each stateless service with a Kubernetes LoadBalancer service.
# AWS Load Balancer Controller / Service annotations can be added for production ALB ingress.
resource "aws_route53_record" "primary" {
  provider = aws.primary
  zone_id = var.hosted_zone_id
  name = var.app_fqdn
  type = "CNAME"
  set_identifier = "primary"
  weighted_routing_policy { weight = 100 }
  ttl = 30
  records = [var.primary_lb_dns]
}
resource "aws_route53_record" "secondary" {
  provider = aws.primary
  zone_id = var.hosted_zone_id
  name = var.app_fqdn
  type = "CNAME"
  set_identifier = "secondary"
  weighted_routing_policy { weight = 0 }
  ttl = 30
  records = [var.secondary_lb_dns]
}
