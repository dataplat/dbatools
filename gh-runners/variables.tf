variable "resource_group_name" {
  description = "Name of the Azure resource group"
  type        = string
}

variable "location" {
  description = "Azure region for resources"
  type        = string
}

variable "vmss_name" {
  description = "Name of the Virtual Machine Scale Set"
  type        = string
}

variable "image_resource_group" {
  description = "Resource group containing the custom image"
  type        = string
}

variable "image_name" {
  description = "Name of the custom VM image"
  type        = string
}

variable "keyvault_name" {
  description = "Name of the Key Vault for secrets"
  type        = string
}

variable "min_instances" {
  description = "Minimum number of VMSS instances"
  type        = number
  default     = 0
}

variable "max_instances" {
  description = "Maximum number of VMSS instances"
  type        = number
  default     = 3
}

variable "github_token" {
  description = "GitHub Personal Access Token for runner registration"
  type        = string
  sensitive   = true
}

variable "github_organization" {
  description = "GitHub organization name"
  type        = string
}

variable "github_repository" {
  description = "GitHub repository name"
  type        = string
}

variable "vm_sku" {
  description = "Azure VM SKU for scale set instances"
  type        = string
  default     = "Standard_B4ms"
}

variable "admin_username" {
  description = "Admin username for VMs"
  type        = string
  default     = "runneradmin"
}

variable "admin_password" {
  description = "Admin password for VMs"
  type        = string
  sensitive   = true
  default     = "dbatools.I00"
}
