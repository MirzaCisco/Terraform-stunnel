# ============================================================================
# Stunnel MQTT Proxy Deployment
# ============================================================================

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.23"
    }
  }
}

provider "azurerm" {
  features {}
  
  # Force use of service principal credentials from environment variables
  use_cli = false
}

# ============================================================================
# Data Sources
# ============================================================================

data "azurerm_kubernetes_cluster" "aks" {
  name                = var.aks_cluster_name
  resource_group_name = var.aks_resource_group
}

provider "kubernetes" {
  host                   = data.azurerm_kubernetes_cluster.aks.kube_config.0.host
  client_certificate     = base64decode(data.azurerm_kubernetes_cluster.aks.kube_config.0.client_certificate)
  client_key             = base64decode(data.azurerm_kubernetes_cluster.aks.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(data.azurerm_kubernetes_cluster.aks.kube_config.0.cluster_ca_certificate)
}

# ============================================================================
# Variables
# ============================================================================

variable "aks_cluster_name" {
  description = "Name of the AKS cluster"
  type        = string
  default     = "aks-stunnel-poc"
}

variable "aks_resource_group" {
  description = "Resource group of the AKS cluster"
  type        = string
  default     = "rg-afm-poc-main"
}

variable "namespace" {
  description = "Kubernetes namespace"
  type        = string
  default     = "mqtt-proxy"
}

variable "stunnel_replicas" {
  description = "Number of Stunnel replicas"
  type        = number
  default     = 2
}

variable "eventgrid_endpoint" {
  description = "Event Grid MQTT endpoint"
  type        = string
  default     = "afm-eg.westeurope-1.ts.eventgrid.azure.net:8883"
}

variable "mqtt_client_cert" {
  description = "MQTT client certificate (base64)"
  type        = string
  sensitive   = true
}

variable "mqtt_client_key" {
  description = "MQTT client key (base64)"
  type        = string
  sensitive   = true
}

variable "enable_cert_verification" {
  description = "Enable certificate verification"
  type        = bool
  default     = false
}

variable "debug_level" {
  description = "Stunnel debug level"
  type        = number
  default     = 7
}

# ============================================================================
# Local Variables
# ============================================================================

locals {
  app_name = "stunnel-proxy"
  labels = {
    app        = local.app_name
    managed_by = "terraform"
  }
}

# ============================================================================
# Kubernetes Resources
# ============================================================================

resource "kubernetes_namespace" "stunnel" {
  metadata {
    name = var.namespace
    labels = local.labels
  }
}

resource "kubernetes_secret" "mqtt_certs" {
  metadata {
    name      = "mqtt-certs"
    namespace = kubernetes_namespace.stunnel.metadata[0].name
    labels    = local.labels
  }

  data = {
    "mqtt-client.crt" = var.mqtt_client_cert
    "mqtt-client.key" = var.mqtt_client_key
  }

  type = "Opaque"
}

resource "kubernetes_deployment" "stunnel_proxy" {
  metadata {
    name      = local.app_name
    namespace = kubernetes_namespace.stunnel.metadata[0].name
    labels    = local.labels
  }

  spec {
    replicas = var.stunnel_replicas

    selector {
      match_labels = {
        app = local.app_name
      }
    }

    template {
      metadata {
        labels = local.labels
      }

      spec {
        affinity {
          pod_anti_affinity {
            preferred_during_scheduling_ignored_during_execution {
              weight = 100
              pod_affinity_term {
                label_selector {
                  match_expressions {
                    key      = "app"
                    operator = "In"
                    values   = [local.app_name]
                  }
                }
                topology_key = "kubernetes.io/hostname"
              }
            }
          }
        }

        container {
          name  = "stunnel"
          image = "alpine:latest"

          port {
            container_port = 1883
            name           = "mqtt"
          }

          command = ["/bin/sh"]
          args = [
            "-c",
            <<-EOT
              apk add --no-cache stunnel
              cat > /etc/stunnel/stunnel.conf <<EOF
              foreground = yes
              debug = 
              
              [mqtt-tls]
              client = yes
              accept = 1883
              connect = 
              verify = 
              cert = /certs/mqtt-client.crt
              key = /certs/mqtt-client.key
              EOF
              
              stunnel /etc/stunnel/stunnel.conf
            EOT
          ]

          resources {
            requests = {
              memory = "64Mi"
              cpu    = "100m"
            }
            limits = {
              memory = "128Mi"
              cpu    = "200m"
            }
          }

          volume_mount {
            name       = "mqtt-certs"
            mount_path = "/certs"
            read_only  = true
          }

          liveness_probe {
            tcp_socket {
              port = 1883
            }
            initial_delay_seconds = 10
            period_seconds        = 30
          }

          readiness_probe {
            tcp_socket {
              port = 1883
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }
        }

        volume {
          name = "mqtt-certs"
          secret {
            secret_name = kubernetes_secret.mqtt_certs.metadata[0].name
          }
        }
      }
    }
  }

  depends_on = [
    kubernetes_secret.mqtt_certs
  ]
}

resource "kubernetes_service" "stunnel_proxy" {
  metadata {
    name      = local.app_name
    namespace = kubernetes_namespace.stunnel.metadata[0].name
    labels    = local.labels
  }

  spec {
    type = "ClusterIP"

    selector = {
      app = local.app_name
    }

    port {
      name        = "mqtt"
      port        = 1883
      target_port = 1883
      protocol    = "TCP"
    }
  }
}

# ============================================================================
# Outputs
# ============================================================================

output "namespace" {
  description = "Kubernetes namespace"
  value       = kubernetes_namespace.stunnel.metadata[0].name
}

output "service_name" {
  description = "Service name"
  value       = kubernetes_service.stunnel_proxy.metadata[0].name
}

output "service_endpoint" {
  description = "Service endpoint"
  value       = "utf8{kubernetes_service.stunnel_proxy.metadata[0].name}.utf8{kubernetes_namespace.stunnel.metadata[0].name}.svc.cluster.local:1883"
}
