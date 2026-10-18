variable "region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  type    = string
  default = "llm-lab"
}

variable "azs" {
  type    = list(string)
  default = ["us-east-1d", "us-east-1b"]
}

variable "kubernetes_version" {
  type    = string
  default = "1.37"
}

variable "my_ip" {
  type        = string
  description = "Your public IP, allowed to reach the EKS API"
}

variable "gpu_capacity_type" {
  type    = string
  default = "SPOT"

  validation {
    condition     = contains(["SPOT", "ON_DEMAND"], var.gpu_capacity_type)
    error_message = "gpu_capacity_type must be SPOT or ON_DEMAND."
  }
}

variable "gpu_node_count" {
  type    = number
  default = 0
}