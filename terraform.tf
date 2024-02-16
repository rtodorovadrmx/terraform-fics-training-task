terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "5.36.0"
    }
  }
  required_version = "~> 1.3"
}

# Configure the AWS Provider
provider "aws" {
  region = "eu-central-1"
}
