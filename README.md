# Stunnel MQTT Proxy - Infrastructure as Code

This repository contains Terraform infrastructure and CI/CD pipelines for deploying a Stunnel MQTT proxy to Azure Kubernetes Service (AKS) to facilitate connections to Azure Event Grid.

## 🏗️ Architecture

\\\
┌─────────────────────────────────────────────────┐
│              Azure Subscription                 │
│                                                 │
│  ┌───────────────────────────────────────────┐ │
│  │       Resource Group                      │ │
│  │       rg-afm-poc-main                     │ │
│  │                                           │ │
│  │  ┌─────────────────────────────────────┐ │ │
│  │  │     AKS Cluster                     │ │ │
│  │  │     aks-stunnel-poc                 │ │ │
│  │  │                                     │ │ │
│  │  │  ┌──────────────────────────────┐  │ │ │
│  │  │  │  Namespace: mqtt-proxy       │  │ │ │
│  │  │  │                              │  │ │ │
│  │  │  │  - Stunnel Deployment (2x)   │  │ │ │
│  │  │  │  - Service (ClusterIP)       │  │ │ │
│  │  │  │  - Secret (Certificates)     │  │ │ │
│  │  │  └──────────────────────────────┘  │ │ │
│  │  └─────────────────────────────────────┘ │ │
│  └───────────────────────────────────────────┘ │
└─────────────────────────────────────────────────┘
                      │
                      │ MQTT over TLS (8883)
                      ▼
┌─────────────────────────────────────────────────┐
│          Azure Event Grid                       │
│   afm-eg.westeurope-1.ts.eventgrid.azure.net   │
└─────────────────────────────────────────────────┘
\\\

## 📁 Repository Structure

\\\
Terraform-stunnel/
├── .github/
│   └── workflows/
│       ├── terraform-plan.yml    # PR validation
│       └── terraform-apply.yml   # Deployment
├── terraform/
│   ├── aks/                      # AKS cluster infrastructure
│   │   ├── main.tf
│   │   └── terraform.tfvars
│   └── stunnel/                  # Stunnel proxy deployment
│       ├── main.tf
│       └── terraform.tfvars
├── certs/                        # Certificates (gitignored)
├── .gitignore
└── README.md
\\\

## 🚀 Quick Start

### Prerequisites

- Azure subscription with contributor access to \g-afm-poc-main\
- GitHub account
- MQTT client certificates

### Setup GitHub Secrets

Navigate to: https://github.com/MirzaCisco/Terraform-stunnel/settings/secrets/actions

Add the following secrets:

| Secret | Description | How to Get |
|--------|-------------|------------|
| \AZURE_CREDENTIALS\ | Service principal JSON | See setup instructions below |
| \AZURE_CLIENT_ID\ | Azure client ID | From service principal |
| \AZURE_CLIENT_SECRET\ | Azure client secret | From service principal |
| \AZURE_SUBSCRIPTION_ID\ | Azure subscription ID | From Azure portal |
| \AZURE_TENANT_ID\ | Azure tenant ID | From Azure portal |
| \MQTT_CLIENT_CERT\ | Client certificate (base64) | Base64 encode your cert |
| \MQTT_CLIENT_KEY\ | Client key (base64) | Base64 encode your key |

### Deploy Infrastructure

1. Push code to \main\ branch
2. GitHub Actions will automatically:
   - Create AKS cluster
   - Deploy Stunnel proxy
   - Verify deployment

### Access Cluster

\\\ash
# Get AKS credentials
az aks get-credentials --resource-group rg-afm-poc-main --name aks-stunnel-poc

# Verify deployment
kubectl get pods -n mqtt-proxy
kubectl get svc -n mqtt-proxy
\\\

## 🧪 Testing

\\\ash
# Create test pod
kubectl run mqtt-test --rm -it --image=eclipse-mosquitto:latest --namespace=mqtt-proxy --restart=Never -- sh

# Inside pod, test MQTT connection
mosquitto_sub -h stunnel-proxy -p 1883 -t command/orders -v
\\\

## 📊 Monitoring

View logs:
\\\ash
kubectl logs -l app=stunnel-proxy -n mqtt-proxy -f
\\\

## 🔧 Local Development

Deploy manually:
\\\ash
# AKS
cd terraform/aks
terraform init
terraform apply

# Stunnel
cd ../stunnel
export TF_VAR_mqtt_client_cert=\
export TF_VAR_mqtt_client_key=\
terraform init
terraform apply
\\\

## 📝 License

MIT

## 👤 Author

Mirza - [GitHub](https://github.com/MirzaCisco)
