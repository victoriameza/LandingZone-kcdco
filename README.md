# 🚀 Azure Landing Zone Demo con Terraform

Este proyecto es un **ejemplo práctico de una Landing Zone en Azure**, orientado a escenarios **cloud-native** con **Kubernetes (AKS)**, gobernanza mediante **Management Groups y Policies**, y seguridad integrada con **Azure Defender** y **Log Analytics**.

El objetivo es mostrar cómo, desde **día cero**, se puede desplegar una plataforma consistente, segura y preparada para múltiples equipos de desarrollo.


## 📂 Estructura del repositorio

* **`main.tf`** → Define la infraestructura principal:

  * Management Groups (Corp, Platform, Sandbox).
  * Políticas de gobernanza (tags obligatorios, ubicaciones permitidas).
  * Log Analytics Workspace + Container Insights.
  * Azure Security Center (Defender for Cloud: VM, AKS, CSPM).
  * Red (VNET + Subnet).
  * AKS con integración de políticas, monitoreo y namespaces (`frontend`, `backend`).

* **`variables.tf`** → Variables de entrada (subscription\_id, prefix, location, etc).

## ⚙️ Prerrequisitos

1. [Terraform >= 1.5](https://developer.hashicorp.com/terraform/downloads).
2. Azure CLI autenticado:

   ```bash
   az login
   ```
3. Una suscripción de Azure con permisos de **Owner** o equivalente.

## 🚀 Despliegue

Ejecutar los siguientes comandos en orden:

```bash
terraform fmt -recursive
terraform init -upgrade
terraform validate
```

### Planificar la infraestructura:

```bash
terraform plan \
  -var="subscription_id=<tu-subscription-id>" \
  -var="prefix=kcdco" \
  -var='allowed_locations=["eastus"]' \
  -var="location=eastus"
```

### Aplicar cambios:

```bash
terraform apply -auto-approve \
  -var="subscription_id=<tu-subscription-id>" \
  -var="prefix=kcdco" \
  -var='allowed_locations=["eastus"]' \
  -var="location=eastus"
```

## 🛡️ Qué se despliega

* **Gobernanza**:

  * Management Groups (`corp`, `platform`, `sandbox`).
  * Políticas (`tags obligatorios`, `ubicaciones permitidas`).

* **Seguridad y observabilidad**:

  * Log Analytics Workspace con Container Insights.
  * Azure Defender habilitado para **VMs, AKS y CSPM**.

* **Plataforma AKS**:

  * Cluster AKS con RBAC y Azure Policy habilitados.
  * Integración con Log Analytics.
  * Namespaces `frontend` y `backend`.

## 🧹 Destrucción

Para eliminar todos los recursos creados:

```bash
terraform destroy \
  -var="subscription_id=<tu-subscription-id>" \
  -var="prefix=kcdco" \
  -var='allowed_locations=["eastus"]' \
  -var="location=eastus"
```

## 📊 Uso en presentaciones

Este repo fue usado en una charla para demostrar:

* Diferencia entre improvisar en la nube vs. planificar con una Landing Zone.
* Cómo las políticas y la seguridad se pueden aplicar desde el día cero.
* Ejemplo práctico de despliegue con Terraform y demo en consola.
