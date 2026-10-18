resource "aws_efs_file_system" "models" {
  creation_token   = "${var.project}-models"
  encrypted        = true
  performance_mode = "generalPurpose"
  throughput_mode  = "bursting"

  tags = {
    Name = "${var.project}-models"
  }
}

resource "aws_security_group" "efs" {
  name_prefix = "${var.project}-efs-"
  description = "Allow NFS from EKS nodes"
  vpc_id      = module.vpc.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "efs_from_nodes" {
  security_group_id            = aws_security_group.efs.id
  referenced_security_group_id = module.eks.node_security_group_id
  from_port                    = 2049
  to_port                      = 2049
  ip_protocol                  = "tcp"
  description                  = "NFS from EKS nodes"
}

resource "aws_efs_mount_target" "models" {
  count           = length(var.azs)
  file_system_id  = aws_efs_file_system.models.id
  subnet_id       = module.vpc.private_subnets[count.index]
  security_groups = [aws_security_group.efs.id]
}