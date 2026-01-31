// ============================================================================
// OpenClaw on Azure Container Apps - Main Orchestrator
// ============================================================================
// This is the main Bicep template that orchestrates all resources.
// Deploy with: az deployment group create -g <resource-group> -f main.bicep
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

@description('Enable Azure Front Door for global distribution (reserved for future use)')
@metadata({ deprecated: true })
param enableFrontDoor bool = false

@description('Enable zone redundancy (higher availability, higher cost)')
param enableZoneRedundancy bool = false

@description('Tags to apply to all resources')
param tags object = {}

// ============================================================================
// VARIABLES
// ============================================================================

// Import shared variables
var envConfig = {
  dev: {
    containerCpu: '0.5'
    containerMemory: '1Gi'
    minReplicas: 1
    maxReplicas: 1
    storageSku: 'Standard_LRS'
    storageQuotaGb: 5
  }
  staging: {
    containerCpu: '1.0'
    containerMemory: '2Gi'
    minReplicas: 1
    maxReplicas: 2
    storageSku: 'Standard_LRS'
    storageQuotaGb: 10
  }
  prod: {
    containerCpu: '2.0'
    containerMemory: '4Gi'
    minReplicas: 2
    maxReplicas: 5
    storageSku: 'Standard_GRS'
    storageQuotaGb: 50
  }
}

var config = envConfig[environment]

// Resource naming with environment suffix
var resourceNames = {
  containerEnv: '${baseName}-env-${environment}'
  containerApp: '${baseName}-app-${environment}'
  storageAccount: '${baseName}st${environment}${uniqueString(resourceGroup().id)}'
  keyVault: '${baseName}-kv-${environment}'
  acr: acrName != '' ? acrName : '${baseName}acr${environment}'
  logAnalytics: '${baseName}-logs-${environment}'
  appInsights: '${baseName}-insights-${environment}'
  managedIdentity: '${baseName}-identity-${environment}'
  fileShare: 'openclaw-data'
}

// Merge default tags with provided tags
var allTags = union({
  application: 'OpenClaw'
  environment: environment
  managedBy: 'Bicep'
  deployedAt: 'deployed'
}, tags)

// ============================================================================
// MODULES
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

// User-Assigned Managed Identity
resource managedIdentity 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: resourceNames.managedIdentity
  location: location
  tags: allTags
}

// Key Vault for secrets
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: resourceNames.keyVault
  location: location
  tags: allTags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: environment == 'prod' ? 90 : 7
    enablePurgeProtection: environment == 'prod' ? true : false
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
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7') // Key Vault Secrets Officer
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Storage Account for persistent data
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: take(replace(toLower(resourceNames.storageAccount), '-', ''), 24)
  location: location
  tags: allTags
  sku: {
    name: config.storageSku
  }
  kind: 'StorageV2'
  properties: {
    accessTier: 'Hot'
    supportsHttpsTrafficOnly: true
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: true // Required for Azure Files mounting
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// File Service for Azure Files
resource fileService 'Microsoft.Storage/storageAccounts/fileServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
}

// File Share for OpenClaw data
resource fileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-01-01' = {
  parent: fileService
  name: resourceNames.fileShare
  properties: {
    shareQuota: config.storageQuotaGb
    accessTier: 'TransactionOptimized'
  }
}

// Storage Blob Data Contributor role for managed identity
resource storageBlobRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, managedIdentity.id, 'Storage Blob Data Contributor')
  scope: storageAccount
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'ba92f5b4-2d11-453d-a403-e96b0029c9fe') // Storage Blob Data Contributor
    principalId: managedIdentity.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// Container Apps Environment
resource containerEnv 'Microsoft.App/managedEnvironments@2023-05-01' = {
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

// Storage mount configuration
resource envStorage 'Microsoft.App/managedEnvironments/storages@2023-05-01' = {
  parent: containerEnv
  name: 'openclaw-storage'
  properties: {
    azureFile: {
      accountName: storageAccount.name
      accountKey: storageAccount.listKeys().keys[0].value
      shareName: resourceNames.fileShare
      accessMode: 'ReadWrite'
    }
  }
}

// Container App
resource containerApp 'Microsoft.App/containerApps@2023-05-01' = {
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
      secrets: [
        {
          name: 'anthropic-api-key'
          keyVaultUrl: '${keyVault.properties.vaultUri}secrets/anthropic-api-key'
          identity: managedIdentity.id
        }
        {
          name: 'gateway-token'
          keyVaultUrl: '${keyVault.properties.vaultUri}secrets/gateway-token'
          identity: managedIdentity.id
        }
      ]
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
          env: [
            { name: 'NODE_ENV', value: environment == 'prod' ? 'production' : 'development' }
            { name: 'ANTHROPIC_API_KEY', secretRef: 'anthropic-api-key' }
            { name: 'GATEWAY_TOKEN', secretRef: 'gateway-token' }
            { name: 'OPENCLAW_WORKSPACE', value: '/data/workspace' }
            { name: 'OPENCLAW_CONFIG', value: '/data/config' }
            { name: 'OPENCLAW_LOG_LEVEL', value: environment == 'prod' ? 'info' : 'debug' }
            { name: 'APPLICATIONINSIGHTS_CONNECTION_STRING', value: appInsights.properties.ConnectionString }
            { name: 'AZURE_CLIENT_ID', value: managedIdentity.properties.clientId }
          ]
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
          storageType: 'AzureFile'
          storageName: 'openclaw-storage'
        }
      ]
    }
  }
  dependsOn: [
    envStorage
    kvSecretsOfficerRole
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

@description('Storage Account Name')
output storageAccountName string = storageAccount.name

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

@description('Environment Configuration')
output environmentConfig object = config
