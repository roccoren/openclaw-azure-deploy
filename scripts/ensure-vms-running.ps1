param(
  [string]$ResourceGroup = "VMS-GROUP",
  [string[]]$VmNames = @()
)

# Authenticate with managed identity
Connect-AzAccount -Identity | Out-Null

# If VmNames not provided, try Automation variable "ensure-vms-list"
if ($VmNames.Count -eq 0) {
  try {
    $var = Get-AutomationVariable -Name "ensure-vms-list" -ErrorAction Stop
    if ($var) {
      try {
        # Prefer JSON array
        $VmNames = (ConvertFrom-Json $var) | ForEach-Object { $_.ToString().Trim() } | Where-Object { $_ }
      } catch {
        # Fallback: comma-separated string
        $VmNames = $var -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ }
      }
    }
  } catch {
    # ignore if variable not found
  }
}

# If still empty, exit (manual list required)
if ($VmNames.Count -eq 0) {
  Write-Output "No VM names provided. Set Automation variable 'ensure-vms-list' or pass -VmNames."
  return
}

foreach ($name in $VmNames) {
  $vm = Get-AzVM -ResourceGroupName $ResourceGroup -Name $name -Status -ErrorAction SilentlyContinue
  if (-not $vm) {
    Write-Output "${name}: not found"
    continue
  }

  $power = ($vm.Statuses | Where-Object { $_.Code -like 'PowerState/*' }).DisplayStatus
  Write-Output "${($vm.Name)}: ${power}"

  if ($power -in @('VM deallocated','VM stopped','VM stopped (deallocated)','VM stopped (generalized)')) {
    Write-Output "Starting ${($vm.Name)}..."
    Start-AzVM -ResourceGroupName $ResourceGroup -Name $vm.Name | Out-Null
  }
}
