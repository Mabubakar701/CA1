terraform {
  # Required version of Terraform CLI
  required_version = ">= 1.0"
  
  # Required providers and their versions
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

# Configure the Azure Provider
provider "azurerm" {
  features {} # Required block for the Azure provider
}