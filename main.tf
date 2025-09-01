terraform {
  required_providers {
    azurerm   = { source = "hashicorp/azurerm",    version = "~> 3.108" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.32" }
    azapi    = { source = "azure/azapi",           version = "~> 1.13" }
  }
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

provider "azapi" {}

# ===== Contexto =====
data "azurerm_client_config" "current" {}
data "azurerm_subscription" "current" {}

# =========================
#   MANAGEMENT GROUPS
# =========================
resource "azurerm_management_group" "corp" {
  display_name               = "${var.prefix}-corp"
  name                       = "${var.prefix}-corp"
  parent_management_group_id = var.parent_management_group_id
}

resource "azurerm_management_group" "platform" {
  display_name               = "${var.prefix}-platform"
  name                       = "${var.prefix}-platform"
  parent_management_group_id = azurerm_management_group.corp.id
}

resource "azurerm_management_group" "sandbox" {
  display_name               = "${var.prefix}-sandbox"
  name                       = "${var.prefix}-sandbox"
  parent_management_group_id = azurerm_management_group.corp.id
}

# Asociar suscripción al MG platform
resource "azurerm_management_group_subscription_association" "platform_assoc" {
  management_group_id = azurerm_management_group.platform.id
  subscription_id     = data.azurerm_subscription.current.id

  depends_on = [
    azurerm_management_group.corp,
    azurerm_management_group.platform
  ]
}

# =========================
#   POLICIES (MG SCOPE)
# =========================
resource "azurerm_policy_definition" "enforce_tags" {
  name                = "${var.prefix}-enforce-tags"
  display_name        = "Require tags 'environment' and 'owner'"
  policy_type         = "Custom"
  mode                = "All"
  management_group_id = azurerm_management_group.corp.id

  policy_rule = jsonencode({
    if = {
      anyOf = [
        { field = "tags['environment']", exists = "false" },
        { field = "tags['owner']",       exists = "false" }
      ]
    }
    then = { effect = "deny" }
  })
}

resource "azurerm_policy_definition" "allowed_locations" {
  name                = "${var.prefix}-allowed-locations"
  display_name        = "Allowed locations (deny non-approved regions)"
  policy_type         = "Custom"
  mode                = "All"
  management_group_id = azurerm_management_group.corp.id

  parameters = jsonencode({
    listOfAllowedLocations = {
      type     = "Array"
      metadata = { displayName = "Allowed locations" }
    }
  })
  policy_rule = jsonencode({
    if = {
      not = {
        field = "location",
        in    = "[parameters('listOfAllowedLocations')]"
      }
    }
    then = { effect = "deny" }
  })
}

resource "azurerm_management_group_policy_assignment" "assign_tags" {
  name                 = "${var.prefix}-assign-tags"
  display_name         = "Enforce required tags"
  management_group_id  = azurerm_management_group.corp.id
  policy_definition_id = azurerm_policy_definition.enforce_tags.id
  depends_on           = [azurerm_policy_definition.enforce_tags]
}

resource "azurerm_management_group_policy_assignment" "assign_locations" {
  name                 = "${var.prefix}-assign-locations"
  display_name         = "Allowed locations"
  management_group_id  = azurerm_management_group.corp.id
  policy_definition_id = azurerm_policy_definition.allowed_locations.id
  parameters = jsonencode({
    listOfAllowedLocations = { value = var.allowed_locations }
  })
  depends_on = [azurerm_policy_definition.allowed_locations]
}

# =========================
#  OBSERVABILIDAD / SEGURIDAD
# =========================
resource "azurerm_resource_group" "platform" {
  name     = "${var.prefix}-rg-platform"
  location = var.location
  tags     = var.default_tags
}

resource "azurerm_log_analytics_workspace" "law" {
  name                = "${var.prefix}-log"
  location            = var.location
  resource_group_name = azurerm_resource_group.platform.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.default_tags
}

resource "azurerm_log_analytics_solution" "container_insights" {
  solution_name         = "ContainerInsights"
  location              = var.location
  resource_group_name   = azurerm_resource_group.platform.name
  workspace_resource_id = azurerm_log_analytics_workspace.law.id
  workspace_name        = azurerm_log_analytics_workspace.law.name

  plan {
    publisher = "Microsoft"
    product   = "OMSGallery/ContainerInsights"
  }

  tags = var.default_tags
}


# Defender for Cloud: vincular workspace
resource "azurerm_security_center_workspace" "mdc_workspace" {
  scope        = data.azurerm_subscription.current.id
  workspace_id = azurerm_log_analytics_workspace.law.id
}

# Planes Defender
resource "azurerm_security_center_subscription_pricing" "kubernetes" {
  resource_type = "KubernetesService"
  tier          = "Standard"
}

resource "azurerm_security_center_subscription_pricing" "vm" {
  resource_type = "VirtualMachines"
  tier          = "Standard"
}

resource "azurerm_security_center_subscription_pricing" "cspm" {
  resource_type = "CloudPosture"
  tier          = "Standard"
}

# =========================
#          RED
# =========================
resource "azurerm_virtual_network" "vnet" {
  name                = "${var.prefix}-vnet"
  location            = var.location
  resource_group_name = azurerm_resource_group.platform.name
  address_space       = ["10.60.0.0/16"]
  tags                = var.default_tags
}

resource "azurerm_subnet" "aks" {
  name                 = "${var.prefix}-snet-aks"
  resource_group_name  = azurerm_resource_group.platform.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.60.10.0/24"]
}

# =========================
#           AKS
# =========================
resource "azurerm_kubernetes_cluster" "aks" {
  name                = "${var.prefix}-aks"
  location            = var.location
  resource_group_name = azurerm_resource_group.platform.name
  dns_prefix          = "${var.prefix}-dns"
  tags                = var.default_tags

  # Sin versión fija: Azure elige una soportada en la región
  sku_tier     = "Free"
  support_plan = "KubernetesOfficial"

  default_node_pool {
    name           = "sysnp"
    vm_size        = "Standard_D2s_v3"
    node_count     = 1
    vnet_subnet_id = azurerm_subnet.aks.id
    type           = "VirtualMachineScaleSets"
    tags           = var.default_tags
  }

  network_profile {
    network_plugin    = "azure"
    load_balancer_sku = "standard"
    outbound_type     = "loadBalancer"
  }

  identity { type = "SystemAssigned" }

  # Gobierno integrado
  azure_policy_enabled              = true
  role_based_access_control_enabled = true

  # Container Insights (AMA/Insights)
  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id
  }

  # Nos aseguramos de que ContainerInsights existe antes (y con tags válidos)
  depends_on = [azurerm_log_analytics_solution.container_insights]
}

# Diagnósticos de AKS -> Log Analytics
resource "azurerm_monitor_diagnostic_setting" "aks_diag" {
  name                       = "${var.prefix}-aks-diag"
  target_resource_id         = azurerm_kubernetes_cluster.aks.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id

  enabled_log { category = "kube-apiserver" }
  enabled_log { category = "kube-audit" }
  enabled_log { category = "guard" }
  metric      { category = "AllMetrics" }
}


# === Defender for Containers ON (vía API nativa de AKS) ===
resource "azapi_update_resource" "defender_on_aks" {
  type        = "Microsoft.ContainerService/managedClusters@2023-08-01"
  resource_id = azurerm_kubernetes_cluster.aks.id

  body = jsonencode({
    properties = {
      securityProfile = {
        defender = {
          logAnalyticsWorkspaceResourceId = azurerm_log_analytics_workspace.law.id
          securityMonitoring = { enabled = true }
        }
      }
    }
  })

  # tolera propiedades que el API omita en la respuesta
  ignore_missing_property = true

  timeouts {
    create = "60m"
    update = "60m"
  }

  depends_on = [
    azurerm_security_center_subscription_pricing.kubernetes,
    azurerm_log_analytics_solution.container_insights
  ]
}



# =========================
#    K8s: NAMESPACES
# =========================
provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.aks.kube_config[0].host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.aks.kube_config[0].cluster_ca_certificate)
}

resource "kubernetes_namespace" "frontend" {
  metadata {
    name = "frontend"
    labels = {
      owner = "team-frontend"
    }
  }
}

resource "kubernetes_namespace" "backend" {
  metadata {
    name = "backend"
    labels = {
      owner = "team-backend"
    }
  }
}

# =========================
#         OUTPUTS
# =========================
output "mg_corp_id" {
  value = azurerm_management_group.corp.id
}
output "policy_tags_assignment_id" {
  value = azurerm_management_group_policy_assignment.assign_tags.id
}
output "policy_locations_assignment_id" {
  value = azurerm_management_group_policy_assignment.assign_locations.id
}
output "log_analytics_id" {
  value = azurerm_log_analytics_workspace.law.id
}
output "aks_name" {
  value = azurerm_kubernetes_cluster.aks.name
}
output "aks_kubeconfig" {
  value     = azurerm_kubernetes_cluster.aks.kube_config_raw
  sensitive = true
}
