// ============================================================================
// OpenClaw - Parameter Definitions
// ============================================================================
// This file contains all parameter definitions with validation.
// Import these in main.bicep or use as a parameters file reference.
// ============================================================================

// ============================================================================
// CORE PARAMETERS
// ============================================================================

@description('Environment name - determines resource sizing and configuration')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'dev'

@description('Azure region for all resources. Defaults to resource group location.')
param location string = resourceGroup().location

@description('Base name for all resources. Used as prefix for naming convention.')
@minLength(3)
@maxLength(15)
param baseName string = 'openclaw'

// ============================================================================
// CONTAINER CONFIGURATION
// ============================================================================

@description('Container image to deploy (e.g., myacr.azurecr.io/openclaw:v1.0.0)')
param containerImage string = ''

@description('Azure Container Registry name (without .azurecr.io suffix)')
param acrName string = ''

@description('Container CPU allocation (0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0)')
@allowed(['0.25', '0.5', '0.75', '1.0', '1.25', '1.5', '1.75', '2.0'])
param containerCpu string = '1.0'

@description('Container memory allocation')
@allowed(['0.5Gi', '1Gi', '2Gi', '3Gi', '4Gi'])
param containerMemory string = '2Gi'

@description('Minimum number of container replicas')
@minValue(0)
@maxValue(30)
param minReplicas int = 1

@description('Maximum number of container replicas')
@minValue(1)
@maxValue(30)
param maxReplicas int = 1

// ============================================================================
// NETWORKING PARAMETERS
// ============================================================================

@description('Enable Azure Front Door for global distribution and WAF')
param enableFrontDoor bool = false

@description('Enable zone redundancy for high availability (increases cost)')
param enableZoneRedundancy bool = false

@description('Custom domain name (optional, e.g., openclaw.contoso.com)')
param customDomain string = ''

@description('Enable virtual network integration')
param enableVnetIntegration bool = false

@description('Virtual network resource ID (required if enableVnetIntegration is true)')
param vnetResourceId string = ''

@description('Subnet name for Container Apps (required if enableVnetIntegration is true)')
param subnetName string = ''

// ============================================================================
// STORAGE PARAMETERS
// ============================================================================

@description('Storage account SKU')
@allowed(['Standard_LRS', 'Standard_GRS', 'Standard_ZRS', 'Standard_GZRS'])
param storageSku string = 'Standard_LRS'

@description('File share quota in GB')
@minValue(1)
@maxValue(5120)
param storageQuotaGb int = 5

// ============================================================================
// MONITORING PARAMETERS
// ============================================================================

@description('Log retention in days')
@minValue(7)
@maxValue(730)
param logRetentionDays int = 30

@description('Enable Application Insights')
param enableAppInsights bool = true

@description('Enable diagnostic settings export to Log Analytics')
param enableDiagnostics bool = true

// ============================================================================
// SECURITY PARAMETERS
// ============================================================================

@description('Enable Key Vault soft delete')
param enableKeyVaultSoftDelete bool = true

@description('Key Vault soft delete retention in days')
@minValue(7)
@maxValue(90)
param keyVaultSoftDeleteDays int = 7

@description('Enable Key Vault purge protection (cannot be disabled once enabled)')
param enableKeyVaultPurgeProtection bool = false

// ============================================================================
// TAGS
// ============================================================================

@description('Tags to apply to all resources')
param tags object = {}

// ============================================================================
// DERIVED VALUES (for export/reference)
// ============================================================================

var defaultTags = {
  application: 'OpenClaw'
  environment: environment
  managedBy: 'Bicep'
}

output mergedTags object = union(defaultTags, tags)
