terraform {
  required_version = ">= 1.0"

  backend "azurerm" {
    resource_group_name  = "dbatools-ci-runners"
    storage_account_name = "dbatoolstfstate"
    container_name       = "tfstate"
    key                  = "vmss.tfstate"
  }

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    github = {
      source  = "integrations/github"
      version = "~> 5.0"
    }
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy = false
    }
  }
}

provider "github" {
  token = var.github_token
  owner = var.github_organization
}
