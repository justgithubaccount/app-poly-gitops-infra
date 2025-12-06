terraform {
  backend "s3" {
    bucket   = "ceae9495-895a43c8-e4e3-424e-9599-6e5b95862164"
    key      = "terraform/infra.tfstate"
    region   = "ru-1"
    endpoint = "https://s3.twcstorage.ru"

    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
  }
}
