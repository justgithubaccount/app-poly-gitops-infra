terraform {
  backend "s3" {
    bucket   = "2038a447-9142-45c8-bcd6-47e98b04fbb2"
    key      = "terraform/infra.tfstate"
    region   = "ru-1"
    endpoint = "s3.timeweb.cloud"

    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
  }
}
