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

@description('Anthropic API Key (will be stored in Key Vault)')
@secure()
param anthropicApiKey string = ''

@description('Gateway Token for OpenClaw authentication (will be stored in Key Vault)')
@secure()
param gatewayToken string = ''

@description('VNet address prefix')
param vnetAddressPrefix string = '10.0.0.0/16'

@description('Container Apps subnet address prefix')
param containerAppsSubnetPrefix string = '10.0.0.0/23'

@description('Private endpoints subnet address prefix')
param privateEndpointSubnetPrefix string = '10.0.2.0/24'

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
    storageQuotaGb: 100  // NFS minimum is 100 GB for Premium
  }
  staging: {
    containerCpu: '1.0'
    containerMemory: '2Gi'
    minReplicas: 1
    maxReplicas: 2
    storageQuotaGb: 100
  }
  prod: {
    containerCpu: '2.0'
    containerMemory: '4Gi'
    minReplicas: 2
    maxReplicas: 5
    storageQuotaGb: 256
  }
}

var config = envConfig[environment]

// Resource naming with environment suffix
var resourceNames = {
  vnet: '${baseName}-vnet-${environment}'
  containerAppsSubnet: 'container-apps-subnet'
  privateEndpointSubnet: 'private-endpoint-subnet'
  containerEnv: '${baseName}-env-${environment}'
  containerApp: '${baseName}-app-${environment}'
  storageAccount: take(toLower('${baseName}nfs${environment}${uniqueString(resourceGroup().id)}'), 24)
  keyVault: '${baseName}-kv-${environment}'
  acr: acrName != '' ? acrName : '${baseName}acr${environment}'
  logAnalytics: '${baseName}-logs-${environment}'
  appInsights: '${baseName}-insights-${environment}'
  managedIdentity: '${baseName}-identity-${environment}'
  fileShare: 'openclaw-data'
  privateEndpoint: '${baseName}-storage-pe-${environment}'
  privateDnsZone: 'privatelink.file.core.windows.net'
}

// Merge default tags with provided tags
var allTags = union({
  application: 'OpenClaw'
  environment: environment
  managedBy: 'Bicep'
  deployedAt: 'deployed'
}, tags)

// ============================================================================
// NETWORKING - VNet and Subnets for NFS
// ============================================================================

// Virtual Network
resource vnet 'Microsoft.Network/virtualNetworks@2023-05-01' = {
  name: resourceNames.vnet
  location: location
  tags: allTags
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    subnets: [
      {
        name: resourceNames.containerAppsSubnet
        properties: {
          addressPrefix: containerAppsSubnetPrefix
          delegations: [
            {
              name: 'Microsoft.App.environments'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
        }
      }
      {
        name: resourceNames.privateEndpointSubnet
        properties: {
          addressPrefix: privateEndpointSubnetPrefix
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

// Reference to subnets
var containerAppsSubnetId = '${vnet.id}/subnets/${resourceNames.containerAppsSubnet}'
var privateEndpointSubnetId = '${vnet.id}/subnets/${resourceNames.privateEndpointSubnet}'

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
// KEY VAULT
// ============================================================================

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
// STORAGE - Premium FileStorage with NFS
// ============================================================================

// Premium FileStorage Account for NFS (no shared key auth needed)
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: resourceNames.storageAccount
  location: location
  tags: allTags
  sku: {
    name: 'Premium_LRS'  // NFS requires Premium
  }
  kind: 'FileStorage'  // NFS requires FileStorage kind
  properties: {
    accessTier: 'Premium'
    supportsHttpsTrafficOnly: false  // NFS uses port 2049, not HTTPS
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false  // Disable key-based auth (compliant with policy)
    publicNetworkAccess: 'Disabled'  // Only accessible via private endpoint
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
    }
  }
}

// File Service for NFS
resource fileService 'Microsoft.Storage/storageAccounts/fileServices@2023-01-01' = {
  parent: storageAccount
  name: 'default'
  properties: {
    protocolSettings: {
      smb: {
        versions: 'SMB3.0;SMB3.1.1'
        authenticationMethods: 'NTLMv2;Kerberos'
        kerberosTicketEncryption: 'RC4-HMAC;AES-256'
        channelEncryption: 'AES-128-CCM;AES-128-GCM;AES-256-GCM'
      }
    }
  }
}

// NFS File Share
resource fileShare 'Microsoft.Storage/storageAccounts/fileServices/shares@2023-01-01' = {
  parent: fileService
  name: resourceNames.fileShare
  properties: {
    shareQuota: config.storageQuotaGb
    enabledProtocols: 'NFS'  // Enable NFS protocol
    rootSquash: 'NoRootSquash'  // Allow root access from container
  }
}

// ============================================================================
// PRIVATE ENDPOINT FOR STORAGE
// ============================================================================

// Private DNS Zone for Azure Files
resource privateDnsZone 'Microsoft.Network/privateDnsZones@2020-06-01' = {
  name: resourceNames.privateDnsZone
  location: 'global'
  tags: allTags
}

// Link Private DNS Zone to VNet
resource privateDnsZoneLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2020-06-01' = {
  parent: privateDnsZone
  name: '${resourceNames.vnet}-link'
  location: 'global'
  properties: {
    registrationEnabled: false
    virtualNetwork: {
      id: vnet.id
    }
  }
}

// Private Endpoint for Storage Account
resource storagePrivateEndpoint 'Microsoft.Network/privateEndpoints@2023-05-01' = {
  name: resourceNames.privateEndpoint
  location: location
  tags: allTags
  properties: {
    subnet: {
      id: privateEndpointSubnetId
    }
    privateLinkServiceConnections: [
      {
        name: '${resourceNames.privateEndpoint}-connection'
        properties: {
          privateLinkServiceId: storageAccount.id
          groupIds: [
            'file'
          ]
        }
      }
    ]
  }
}

// DNS Zone Group for Private Endpoint
resource privateEndpointDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2023-05-01' = {
  parent: storagePrivateEndpoint
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-file-core-windows-net'
        properties: {
          privateDnsZoneId: privateDnsZone.id
        }
      }
    ]
  }
}

// ============================================================================
// CONTAINER APPS ENVIRONMENT (with VNet)
// ============================================================================

// Container Apps Environment with VNet integration
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
    vnetConfiguration: {
      infrastructureSubnetId: containerAppsSubnetId
      internal: false  // Still externally accessible via ingress
    }
    zoneRedundant: enableZoneRedundancy
    daprAIInstrumentationKey: appInsights.properties.InstrumentationKey
  }
  dependsOn: [
    privateDnsZoneLink  // Ensure DNS is ready before Container Apps
  ]
}

// NFS Storage mount configuration (no account key needed!)
resource envStorage 'Microsoft.App/managedEnvironments/storages@2023-05-01' = {
  parent: containerEnv
  name: 'openclaw-storage'
  properties: {
    nfsAzureFile: {
      server: '${storageAccount.name}.file.core.windows.net'
      shareName: resourceNames.fileShare
      accessMode: 'ReadWrite'
    }
  }
  dependsOn: [
    fileShare
    storagePrivateEndpoint
    privateEndpointDnsGroup
  ]
}

// ============================================================================
// CONTAINER APP
// ============================================================================

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
          storageType: 'NfsAzureFile'  // NFS mount type
          storageName: 'openclaw-storage'
        }
      ]
    }
  }
  dependsOn: [
    envStorage
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

@description('VNet Name')
output vnetName string = vnet.name

@description('VNet ID')
output vnetId string = vnet.id

@description('Environment Configuration')
output environmentConfig object = config
