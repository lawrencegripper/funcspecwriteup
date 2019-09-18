resource "azurerm_resource_group" "test" {
  name     = "funcRestSpecTest"
  location = "westeurope"
}

resource "random_string" "random" {
  length = 5
  special = false
  number = true 
  upper = false
  lower = true
}
 
resource "azurerm_storage_account" "test" {
  name                     = "teststorage${random_string.random.result}"
  resource_group_name      = "${azurerm_resource_group.test.name}"
  location                 = "${azurerm_resource_group.test.location}"
  account_tier             = "Standard"
  account_replication_type = "LRS"
}
resource "azurerm_app_service_plan" "test" {
  name                = "testplan${random_string.random.result}"
  location            = "${azurerm_resource_group.test.location}"
  resource_group_name = "${azurerm_resource_group.test.name}"
  sku {
    tier = "Standard"
    size = "S1"
  }
}
resource "azurerm_storage_container" "test" {
  name                  = "function-releases"
  storage_account_name  = "${azurerm_storage_account.test.name}"
  container_access_type = "container"
}
resource "azurerm_storage_blob" "javazip" {
  name = "testfunc.zip"
  resource_group_name    = "${azurerm_resource_group.test.name}"
  storage_account_name   = "${azurerm_storage_account.test.name}"
  storage_container_name = "${azurerm_storage_container.test.name}"
  type   = "block"
  source = "testdata/testfunc.zip"
}
resource "azurerm_function_app" "test" {
  name                      = "testfunc${random_string.random.result}"
  location                  = "${azurerm_resource_group.test.location}"
  resource_group_name       = "${azurerm_resource_group.test.name}"
  app_service_plan_id       = "${azurerm_app_service_plan.test.id}"
  storage_connection_string = "${azurerm_storage_account.test.primary_connection_string}"
  app_settings = {
    WEBSITE_RUN_FROM_PACKAGE = "https://${azurerm_storage_account.test.name}.blob.core.windows.net/${azurerm_storage_container.test.name}/testfunc.zip"
    FUNCTIONS_WORKER_RUNTIME = "node"
  }
}

output "function_endpoint" {
  value = "${azurerm_function_app.test.id}/functions/testfunc"
}

output "site_endpoint" {
  value = "${azurerm_function_app.test.id}"
}