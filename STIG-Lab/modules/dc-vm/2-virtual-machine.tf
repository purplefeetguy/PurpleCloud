locals {
  virtual_machine_name = "${var.prefix}-dc1"
  virtual_machine_fqdn = "${local.virtual_machine_name}.${var.ad_domain}"
  custom_data_params   = "Param($RemoteHostName = \"${local.virtual_machine_fqdn}\", $ComputerName = \"${local.virtual_machine_name}\")"
  custom_data         = base64encode(join(" ", [local.custom_data_params, data.template_file.ps_template.rendered ]))

}

data "template_file" "ps_template" {
  template = file("${path.module}/files/bootstrap.ps1")

  vars  = {
  
    winrm_username            = var.winrm_username
    winrm_password            = var.winrm_password
    admin_username            = var.admin_username
    admin_password            = var.admin_password
    ad_domain                 = var.ad_domain
    prefix                    = var.prefix
    ou			      = var.ou

  }
}

resource "local_file" "debug_bootstrap_script" {
  # For inspecting the rendered powershell script as it is loaded onto endpoint through custom_data extension
  content = data.template_file.ps_template.rendered
  filename = "${path.module}/output/bootstrap.ps1"
}


resource "azurerm_windows_virtual_machine" "domain-controller" {
  name                          = local.virtual_machine_name
  location                      = var.location
  resource_group_name           = var.resource_group_name
  size                       = "Standard_A1"
  computer_name  = local.virtual_machine_name
  admin_username = var.admin_username
  admin_password = var.admin_password
  custom_data    = local.custom_data

  network_interface_ids         = [
    azurerm_network_interface.primary.id,
  ]

  os_disk {
    caching           = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-Datacenter"
    version   = "latest"
  }

  additional_unattend_content {
      content      = "<AutoLogon><Password><Value>${var.admin_password}</Value></Password><Enabled>true</Enabled><LogonCount>1</LogonCount><Username>${var.admin_username}</Username></AutoLogon>"
      setting = "AutoLogon"
  }

  additional_unattend_content {
      content      = file("${path.module}/files/FirstLogonCommands.xml")
      setting = "FirstLogonCommands"
  }

}

resource "azurerm_virtual_machine_extension" "create-ad-forest" {
  name                 = "create-active-directory-forest"
  virtual_machine_id   = azurerm_windows_virtual_machine.domain-controller.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.9"
  settings = <<SETTINGS
  {
    "commandToExecute": "powershell.exe -Command \"${local.powershell_command}\""
  }
SETTINGS
}

resource "local_file" "hosts_cfg" {
  content = templatefile("${path.module}/templates/hosts.tpl",
    {
      ip    = azurerm_public_ip.dc1-external.ip_address
      auser = var.admin_username
      apwd  = var.admin_password
    }
  )
  filename = "${path.module}/hosts.cfg"

}
