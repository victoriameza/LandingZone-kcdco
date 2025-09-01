variable "prefix" {
  description = "Prefijo para nombres de recursos"
  type        = string
  default     = "kcd"
}

variable "subscription_id" {
  description = "ID de la suscripción donde se desplegará la plataforma"
  type        = string
}

variable "parent_management_group_id" {
  description = "ID del Management Group padre (puede ser null para raíz)"
  type        = string
  default     = null
}

variable "location" {
  description = "Región principal"
  type        = string
  default     = "eastus"
}

variable "allowed_locations" {
  description = "Regiones permitidas por política"
  type        = list(string)
  default     = ["eastus", "eastus2"]
}

variable "k8s_version" {
  description = "Versión de Kubernetes para AKS"
  type        = string
  default     = "1.29.7"
}

variable "default_tags" {
  description = "Tags globales obligatorios"
  type        = map(string)
  default = {
    environment = "demo"
    owner       = "platform-team"
    costCenter  = "KCD"
  }
}
variable "enable_defender_extension" {
  type    = bool
  default = false
  description = "Instala la extensión Defender en AKS si la región/tenant lo soporta."
}

