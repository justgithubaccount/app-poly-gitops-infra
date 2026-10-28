terraform {
  required_version = ">= 1.6, < 2.0"

  required_providers {
    twc = {
      source  = "timeweb-cloud/timeweb-cloud"
      version = "~> 1.8"
    }
  }
}
