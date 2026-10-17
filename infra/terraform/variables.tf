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