param(
  [string]$ResourceGroup = "VMS-GROUP",
  [string[]]$VmNames = @()
)

# Authenticate with managed identity
Connect-AzAccount -Identity | Out-Null

# Get target VMs
$targets = @()
if ($VmNames.Count -gt 0) {
  foreach ($name in $VmNames) {
    $vm = Get-AzVM -ResourceGroupName $ResourceGroup -Name $name -Status -ErrorAction SilentlyContinue
    if ($vm) { $targets += $vm }
  }
} else {
  $targets = Get-AzVM -ResourceGroupName $ResourceGroup -Status
}

foreach ($vm in $targets) {
  $power = ($vm.Statuses | Where-Object { $_.Code -like 'PowerState/*' }).DisplayStatus
  Write-Output "${($vm.Name)}: ${power}"

  if ($power -in @('VM deallocated','VM stopped','VM stopped (deallocated)','VM stopped (generalized)')) {
    Write-Output "Starting ${($vm.Name)}..."
    Start-AzVM -ResourceGroupName $ResourceGroup -Name $vm.Name | Out-Null
  }
}
