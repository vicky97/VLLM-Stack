module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.0" # after it works, replace with the exact version from the registry page

  name = "${var.project}-vpc"
  cidr = "10.0.0.0/16"
  azs  = var.azs

  private_subnets = ["10.0.0.0/20", "10.0.16.0/20"]
  public_subnets  = ["10.0.100.0/24", "10.0.101.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = true

  enable_dns_support   = true
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }
}