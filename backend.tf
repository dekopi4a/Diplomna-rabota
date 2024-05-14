terraform {
  backend "s3" {
    bucket         = "davidgigov"
    key            = "path/to/your/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "daviddynamodb"
    encrypt        = true
  }
}
