# --- VARIABLES (Optional but good practice to define location) ---
variable "location" {
  description = "The Azure region to deploy resources in"
  default     = "francecentral" # This region allowed to create VM faced some issue with other region
]}

# --- 1. RESOURCE GROUP ---
resource "azurerm_resource_group" "rg" {
  name     = "DevOps-Server-RG"
  location = var.location
}

# --- 2. NETWORKING ---

# Virtual Network (VNet)
resource "azurerm_virtual_network" "vnet" {
  name                = "DevOps-VNet"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  address_space       = ["10.0.0.0/16"]
}

# Subnet within the VNet
resource "azurerm_subnet" "subnet" {
  name                 = "DevOps-Subnet"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# Network Security Group (NSG) - Firewall rules
resource "azurerm_network_security_group" "nsg" {
  name                = "DevOps-NSG"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  # Allow SSH access (required for Ansible)
  security_rule {
    name                       = "AllowSSH"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "0.0.0.0/0"
    destination_address_prefix = "*"
  }

  # Allow HTTP access (required for the Docker web app)
  security_rule {
    name                       = "AllowHTTP"
    priority                   = 101
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "0.0.0.0/0"
    destination_address_prefix = "*"
  }
}

# Public IP Address for external access
resource "azurerm_public_ip" "publicip" {
  name                = "DevOps-PublicIP"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"  # Changed from Basic (default) to Standard SKU
}

# Network Interface Card (NIC) connecting the VM to the network
resource "azurerm_network_interface" "nic" {
  name                = "DevOps-NIC"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.publicip.id
  }
}

# Associate the NIC with the NSG (apply firewall rules)
resource "azurerm_network_interface_security_group_association" "nic_nsg_association" {
  network_interface_id      = azurerm_network_interface.nic.id
  network_security_group_id = azurerm_network_security_group.nsg.id
}

# --- 3. LINUX VIRTUAL MACHINE (The Server) ---
resource "azurerm_linux_virtual_machine" "vm" {
  name                  = "DevOps-Container-Server"
  resource_group_name   = azurerm_resource_group.rg.name
  location              = azurerm_resource_group.rg.location
  size                  = "Standard_B1s" # A small, cost-effective size for the assignment
  admin_username        = "azureuser"    # Default user for SSH/Ansible
  network_interface_ids = [azurerm_network_interface.nic.id]
  disable_password_authentication = true # Highly secure, relies on SSH key


  # Insert your local public key here
  admin_ssh_key {
    username   = "azureuser"
    public_key = file("C:/Users/Home/.ssh/id_rsa.pub") # <<< CHECK THIS PATH ///username >>>
  }
  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS" # Or Premium_LRS for better performance
    disk_size_gb         = 30             # Optional: Defines the size of the OS disk. Default is often 30GB.
  }

  # Choose a clean Ubuntu 20.04 image
  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-focal"
    sku       = "20_04-lts-gen2"
    version   = "latest"
  }
}