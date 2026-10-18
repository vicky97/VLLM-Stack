module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = var.project
  kubernetes_version = var.kubernetes_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  endpoint_public_access       = true
  endpoint_public_access_cidrs = ["${var.my_ip}/32"]
  endpoint_private_access      = true

  enable_cluster_creator_admin_permissions = true

  addons = {
    coredns                = {}
    kube-proxy             = {}
    vpc-cni                = { before_compute = true }
    eks-pod-identity-agent = { before_compute = true }
  }

  eks_managed_node_groups = {
    cpu = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = ["t3.xlarge"]
      min_size       = 1
      max_size       = 1
      desired_size   = 1
    }

    gpu = {
      ami_type       = "AL2023_x86_64_NVIDIA"
      instance_types = ["g6.2xlarge"]
      capacity_type  = var.gpu_capacity_type
      min_size       = 0
      max_size       = 2
      desired_size   = var.gpu_node_count
      subnet_ids     = [module.vpc.private_subnets[0]]

      block_device_mappings = {
        xvda = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size = 100
            volume_type = "gp3"
          }
        }
      }

      labels = {
        workload = "inference"
      }

      taints = {
        gpu = {
          key    = "nvidia.com/gpu"
          value  = "true"
          effect = "NO_SCHEDULE"
        }
      }
    }
  }
}