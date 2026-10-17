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