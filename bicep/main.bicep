// ============================================================================
// OpenClaw on Azure Container Apps - Main Orchestrator (Ephemeral Storage)
// ============================================================================
// This is the main Bicep template that orchestrates all resources.
// Deploy with: az deployment group create -g <resource-group> -f main.bicep
// 
// NOTE: Uses ephemeral storage for dev. For persistent storage, request
// NFS preview access or use Azure Policy exemption for storage account keys.
// ============================================================================

targetScope = 'resourceGroup'

// ============================================================================
// PARAMETERS
// ============================================================================

@description('Environment name (dev, staging, prod)')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('Azure region for all resources')
param location string = resourceGroup().location

@description('Base name for all resources (lowercase, no special chars)')
@minLength(3)
@maxLength(15)
param baseName string = 'openclaw'

@description('Container image to deploy')
param containerImage string = ''

@description('Azure Container Registry name (without .azurecr.io)')
param acrName string = ''

@description('Enable zone redundancy (higher availability, higher cost)')
param enableZoneRedundancy bool = false

@description('Tags to apply to all resources')
param tags object = {}

@description('Anthropic API Key (will be stored in Key Vault)')
@secure()
param anthropicApiKey string = ''

@description('Gateway Token for OpenClaw authentication (will be stored in Key Vault)')
@secure()
param gatewayToken string = ''

@description('Set to true to recover a soft-deleted Key Vault')
param recoverKeyVault bool = false

// ============================================================================
// VARIABLES
// ============================================================================

var envConfig = {
  dev: {
    containerCpu: '2.0'
    containerMemory: '4Gi'
    minReplicas: 1
    maxReplicas: 1
  }
  staging: {
    containerCpu: '1.0'
    containerMemory: '2Gi'
    minReplicas: 1
    maxReplicas: 2
  }
  prod: {
    containerCpu: '2.0'
    containerMemory: '4Gi'
    minReplicas: 2
    maxReplicas: 5
  }
}

var config = envConfig[environment]

// Resource naming with environment suffix
var resourceNames = {
  containerEnv: '${baseName}-env-${environment}'
  containerApp: '${baseName}-app-${environment}'
  keyVault: '${baseName}-kv-${environment}'
  logAnalytics: '${baseName}-logs-${environment}'
  appInsights: '${baseName}-insights-${environment}'
  managedIdentity: '${baseName}-identity-${environment}'
}

// Merge default tags with provided tags
var allTags = union({
  application: 'OpenClaw'
  environment: environment
  managedBy: 'Bicep'
  storageMode: 'ephemeral'
}, tags)

// ============================================================================
// MONITORING
// ============================================================================

// Log Analytics Workspace for monitoring
resource logAnalytics 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: resourceNames.logAnalytics
  location: location
  tags: allTags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: environment == 'prod' ? 90 : 30
    features: {
      enableLogAccessUsingOnlyResourcePermissions: true
    }
  }
}

// Application Insights for APM
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: resourceNames.appInsights
  location: location
  tags: allTags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: logAnalytics.id
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// ============================================================================
// IDENTITY
// ============================================================================

// User-Assigned Managed Identity
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: resourceNames.managedIdentity
  location: location
  tags: allTags
}

// ============================================================================
// CONTAINER REGISTRY ACCESS
// ============================================================================

// Reference existing ACR (if provided)
resource acr 'Microsoft.ContainerRegistry/registries@2023-07-01' existing = if (acrName != '') {
  name: acrName
}

// Grant AcrPull role to managed identity for container pulls
// ACR Built-in role: AcrPull (7f951dda-4ed3-4680-a7ca-43fe172d538d)
resource acrPullRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (acrName != '') {
  scope: acr
  name: guid(acr.id, managedIdentity.id, 'AcrPull')
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}
// ============================================================================
// KEY VAULT
// ============================================================================

// Key Vault for secrets
// NOTE: Once purge protection is enabled, it cannot be disabled. We always enable it
// for safety, but this means the KV cannot be deleted for 90 days if purged.
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: resourceNames.keyVault
  location: location
  tags: allTags
  properties: {
    createMode: recoverKeyVault ? 'recover' : 'default'
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: environment == 'prod' ? 90 : 7
    // IMPORTANT: Once enabled, purge protection cannot be disabled.
    // We always enable it for safety. Once set, it's permanent for that vault.
    enablePurgeProtection: true
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// Key Vault Secrets Officer role for managed identity
resource kvSecretsOfficerRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.id, managedIdentity.id, 'Key Vault Secrets Officer')
  scope: keyVault
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7')
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Key Vault Secret: Anthropic API Key (only create if provided)
resource anthropicApiKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = if (anthropicApiKey != '') {
  parent: keyVault
  name: 'anthropic-api-key'
  properties: {
    value: anthropicApiKey
    contentType: 'text/plain'
  }
}

// Key Vault Secret: Gateway Token (only create if provided)
resource gatewayTokenSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = if (gatewayToken != '') {
  parent: keyVault
  name: 'gateway-token'
  properties: {
    value: gatewayToken
    contentType: 'text/plain'
  }
}

// ============================================================================
// CONTAINER APPS ENVIRONMENT (Consumption only, no VNet)
// ============================================================================

// Container Apps Environment - simple consumption model
resource containerEnv 'Microsoft.App/managedEnvironments@2024-03-01' = {
  name: resourceNames.containerEnv
  location: location
  tags: allTags
  properties: {
    appLogsConfiguration: {
      destination: 'log-analytics'
      logAnalyticsConfiguration: {
        customerId: logAnalytics.properties.customerId
        sharedKey: logAnalytics.listKeys().primarySharedKey
      }
    }
    zoneRedundant: enableZoneRedundancy
    daprAIInstrumentationKey: appInsights.properties.InstrumentationKey
  }
}

// ============================================================================
// CONTAINER APP
// ============================================================================

// Container App with ephemeral storage
resource containerApp 'Microsoft.App/containerApps@2024-03-01' = {
  name: resourceNames.containerApp
  location: location
  tags: allTags
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${managedIdentity.id}': {}
    }
  }
  properties: {
    managedEnvironmentId: containerEnv.id
    configuration: {
      activeRevisionsMode: 'Single'
      ingress: {
        external: true
        targetPort: 18789
        transport: 'http'
        allowInsecure: false
        corsPolicy: {
          allowedOrigins: ['*']
          allowedMethods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS']
          allowedHeaders: ['*']
          maxAge: 3600
        }
        traffic: [
          {
            latestRevision: true
            weight: 100
          }
        ]
      }
      registries: acrName != '' ? [
        {
          server: '${acrName}.azurecr.io'
          identity: managedIdentity.id
        }
      ] : []
      // Only include secrets that have been configured in Key Vault
      secrets: union(
        anthropicApiKey != '' ? [
          {
            name: 'anthropic-api-key'
            keyVaultUrl: '${keyVault.properties.vaultUri}secrets/anthropic-api-key'
            identity: managedIdentity.id
          }
        ] : [],
        gatewayToken != '' ? [
          {
            name: 'gateway-token'
            keyVaultUrl: '${keyVault.properties.vaultUri}secrets/gateway-token'
            identity: managedIdentity.id
          }
        ] : []
      )
    }
    template: {
      containers: [
        {
          name: 'openclaw'
          image: containerImage != '' ? containerImage : 'mcr.microsoft.com/azuredocs/containerapps-helloworld:latest'
          resources: {
            cpu: json(config.containerCpu)
            memory: config.containerMemory
          }
          env: union(
            [
              { name: 'NODE_ENV', value: environment == 'prod' ? 'production' : 'development' }
              { name: 'OPENCLAW_WORKSPACE', value: '/data/workspace' }
              { name: 'OPENCLAW_CONFIG', value: '/data/config' }
              { name: 'OPENCLAW_LOG_LEVEL', value: environment == 'prod' ? 'info' : 'debug' }
              { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsights.properties.ConnectionString }
              { name: 'AZURE_CLIENT_ID', value: managedIdentity.properties.clientId }
            ],
            anthropicApiKey != '' ? [{ name: 'ANTHROPIC_API_KEY', secretRef: 'anthropic-api-key' }] : [],
            gatewayToken != '' ? [{ name: 'GATEWAY_TOKEN', secretRef: 'gateway-token' }] : []
          )
          volumeMounts: [
            {
              volumeName: 'data'
              mountPath: '/data'
            }
          ]
          probes: [
            {
              type: 'Liveness'
              httpGet: {
                path: '/health'
                port: 18789
              }
              initialDelaySeconds: 60
              periodSeconds: 30
              failureThreshold: 3
              timeoutSeconds: 10
            }
            {
              type: 'Readiness'
              httpGet: {
                path: '/health'
                port: 18789
              }
              initialDelaySeconds: 30
              periodSeconds: 10
              failureThreshold: 3
              timeoutSeconds: 5
            }
            {
              type: 'Startup'
              httpGet: {
                path: '/health'
                port: 18789
              }
              initialDelaySeconds: 10
              periodSeconds: 10
              failureThreshold: 30
              timeoutSeconds: 5
            }
          ]
        }
      ]
      scale: {
        minReplicas: config.minReplicas
        maxReplicas: config.maxReplicas
        rules: environment == 'prod' ? [
          {
            name: 'http-scale'
            http: {
              metadata: {
                concurrentRequests: '50'
              }
            }
          }
        ] : []
      }
      volumes: [
        {
          name: 'data'
          storageType: 'EmptyDir'  // Ephemeral storage - data lost on restart
        }
      ]
    }
  }
  dependsOn: [
    kvSecretsOfficerRole
    anthropicApiKeySecret
    gatewayTokenSecret
  ]
}

// ============================================================================
// OUTPUTS
// ============================================================================

@description('Container App URL')
output containerAppUrl string = 'https://${containerApp.properties.configuration.ingress.fqdn}'

@description('Container App Name')
output containerAppName string = containerApp.name

@description('Container Apps Environment Name')
output containerEnvName string = containerEnv.name

@description('Key Vault Name')
output keyVaultName string = keyVault.name

@description('Key Vault URI')
output keyVaultUri string = keyVault.properties.vaultUri

@description('Managed Identity Client ID')
output managedIdentityClientId string = managedIdentity.properties.clientId

@description('Managed Identity Principal ID')
output managedIdentityPrincipalId string = managedIdentity.properties.principalId

@description('Log Analytics Workspace ID')
output logAnalyticsWorkspaceId string = logAnalytics.properties.customerId

@description('Application Insights Connection String')
output appInsightsConnectionString string = appInsights.properties.ConnectionString

@description('Resource Group Name')
output resourceGroupName string = resourceGroup().name

@description('Storage Mode')
output storageMode string = 'ephemeral'

@description('Environment Configuration')
output environmentConfig object = config
