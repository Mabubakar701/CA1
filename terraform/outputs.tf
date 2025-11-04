output "public_ip_address" {
  description = "The public IP address of the deployed Linux VM"
  value       = azurerm_public_ip.publicip.ip_address
}