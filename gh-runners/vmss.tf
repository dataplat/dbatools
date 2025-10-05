# Get current Azure context
data "azurerm_client_config" "current" {}

# Reference existing resource group
data "azurerm_resource_group" "rg" {
  name = var.resource_group_name
}

# Reference existing Key Vault
data "azurerm_key_vault" "vmss" {
  name                = var.keyvault_name
  resource_group_name = data.azurerm_resource_group.rg.name
}

# Reference existing custom image
data "azurerm_image" "golden" {
  name                = var.image_name
  resource_group_name = var.image_resource_group
}

# Create virtual network for VMSS
resource "azurerm_virtual_network" "vnet" {
  name                = "${var.vmss_name}-vnet"
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = data.azurerm_resource_group.rg.location
  address_space       = ["10.0.0.0/16"]

  tags = {
    Environment = "CI"
    ManagedBy   = "Terraform"
  }
}

# Create subnet for VMSS
resource "azurerm_subnet" "subnet" {
  name                 = "${var.vmss_name}-subnet"
  resource_group_name  = data.azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Windows Virtual Machine Scale Set with custom image
resource "azurerm_windows_virtual_machine_scale_set" "vmss" {
  name                = var.vmss_name
  computer_name_prefix = "dbt"
  resource_group_name = data.azurerm_resource_group.rg.name
  location            = data.azurerm_resource_group.rg.location
  sku                 = var.vm_sku
  instances           = var.min_instances
  admin_username      = var.admin_username
  admin_password      = var.admin_password

  # Use custom golden image with SQL Server pre-installed
  source_image_id = data.azurerm_image.golden.id

  # Enable managed identity for Key Vault access
  identity {
    type = "SystemAssigned"
  }

  # Ephemeral OS disk for faster provisioning and auto-cleanup
  os_disk {
    caching              = "ReadOnly"
    storage_account_type = "Standard_LRS"
    diff_disk_settings {
      option = "Local"
    }
  }

  # Network configuration
  network_interface {
    name    = "vmss-nic"
    primary = true

    ip_configuration {
      name      = "internal"
      primary   = true
      subnet_id = azurerm_subnet.subnet.id
    }
  }

  # Ignore instance count changes (managed by Azure autoscale or manual)
  lifecycle {
    ignore_changes = [instances]
  }

  tags = {
    Environment = "CI"
    ManagedBy   = "Terraform"
    Purpose     = "GitHub-Actions-Runners"
  }
}

# Custom script extension to configure GitHub Actions runner
resource "azurerm_virtual_machine_scale_set_extension" "vmss" {
  name                         = "CustomScriptExtension"
  virtual_machine_scale_set_id = azurerm_windows_virtual_machine_scale_set.vmss.id
  publisher                    = "Microsoft.Compute"
  type                         = "CustomScriptExtension"
  type_handler_version         = "1.10"
  auto_upgrade_minor_version   = true

  # Embed init.ps1 script inline to avoid external dependencies
  protected_settings = jsonencode({
    commandToExecute = "powershell -ExecutionPolicy Unrestricted -Command \"[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String('${base64encode(file("${path.module}/init.ps1"))}')) | Set-Content -Path init.ps1 -Encoding UTF8; & .\\init.ps1\""
  })
}

# Grant VMSS managed identity access to Key Vault secrets
resource "azurerm_role_assignment" "vmss_kv_secrets_user" {
  scope                = data.azurerm_key_vault.vmss.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_windows_virtual_machine_scale_set.vmss.identity[0].principal_id

  # Wait for VMSS to be created
  depends_on = [azurerm_windows_virtual_machine_scale_set.vmss]
}
