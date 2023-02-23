# Create the resource group
resource "azurerm_resource_group" "rg" {
  name     = "rg-terraforn-ansible"
  location = "canadacentral"
}

# Create a VNET
resource "azurerm_virtual_network" "vnet" {
  name                = "terraform-ansible-vnet"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "subnet" {
  name                 = "vm"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Create a public IP
resource "azurerm_public_ip" "pip" {
  name                = "pip-terraform-ansible"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  allocation_method   = "Static"
}

# Get the existing DNS zone
data "azurerm_dns_zone" "dns_zone" {
  name                = "az.coffeetime.dev"
  resource_group_name = "rg-dns"
}

# Create a DNS record
resource "azurerm_dns_a_record" "dns_entry" {
  name                = "terraform-ansible-demo"
  resource_group_name = "rg-dns"
  zone_name           = data.azurerm_dns_zone.dns_zone.name
  ttl                 = 1
  target_resource_id  = azurerm_public_ip.pip.id
}

# Create a NIC
resource "azurerm_network_interface" "nic" {
  name                = "nic-terraform-ansible"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip.id
  }
}

# Get an existing keyvault
data "azurerm_key_vault" "kv" {
  name                = "kv-mgmt-coffeetimedev"
  resource_group_name = "rg-keyvault"
}

# Get an existing secret
data "azurerm_key_vault_secret" "secret" {
  name         = "vm-secret"
  key_vault_id = data.azurerm_key_vault.kv.id
}

# Create a VM
resource "azurerm_linux_virtual_machine" "packer" {
  name                = "vm-terraform-ansible"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location

  size                = "Standard_B1s"
  admin_username      = "adminuser"
  disable_password_authentication = false
  admin_password = data.azurerm_key_vault_secret.secret.value

  network_interface_ids = [
    azurerm_network_interface.nic.id,
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts-gen2"
    version   = "latest"
  }
}

# Get the IP address
output "vm_ip_addr" {
  value = azurerm_public_ip.pip.ip_address
  sensitive = false
}

# Get the VM password
output "vm_secret" {
  value = data.azurerm_key_vault_secret.secret.value
  sensitive = true
}