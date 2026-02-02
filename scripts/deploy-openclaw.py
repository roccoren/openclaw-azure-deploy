#!/usr/bin/env python3
"""
deploy-openclaw.py — Deploy OpenClaw to Azure Container Apps or Azure VM

Usage:
    python deploy-openclaw.py vm --name my-openclaw --location westus2
    python deploy-openclaw.py aca --name my-openclaw --location westus2

Examples:
    # Deploy to VM with spot pricing (default)
    python deploy-openclaw.py vm --name openclaw-prod --location westus2

    # Deploy to VM without spot pricing
    python deploy-openclaw.py vm --name openclaw-prod --location westus2 --no-spot

    # Deploy to Azure Container Apps
    python deploy-openclaw.py aca --name openclaw-staging --location westus2

    # Reuse existing resource group
    python deploy-openclaw.py vm --name my-openclaw --location westus2 --resource-group VMS-GROUP

    # Reuse existing VNet and subnet
    python deploy-openclaw.py vm --name my-openclaw --location westus2 --resource-group VMS-GROUP \
        --vnet-name existing-vnet --subnet-name existing-subnet

    # Dry run (preview commands)
    python deploy-openclaw.py vm --name test --location westus2 --dry-run
"""

import argparse
import ipaddress
import json
import secrets
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional


# =============================================================================
# Configuration
# =============================================================================

@dataclass
class DeployConfig:
    """Deployment configuration."""
    target: str  # "vm" or "aca"
    name: str
    location: str
    resource_group: Optional[str] = None
    
    # VM-specific
    use_spot: bool = True
    vm_size: str = "Standard_D2als_v6"
    vnet_prefix: str = ""  # Auto-calculated if not specified
    subnet_prefix: str = ""  # Auto-calculated if not specified
    vnet_name: Optional[str] = None  # Existing VNet to reuse
    subnet_name: Optional[str] = None  # Existing subnet to reuse
    ssh_key_path: str = field(default_factory=lambda: str(Path.home() / ".ssh" / "id_rsa.pub"))
    os_image: str = "Canonical:ubuntu-24_04-lts:server:latest"
    admin_username: str = "azureuser"
    
    # ACA-specific
    aca_cpu: float = 1.0
    aca_memory: str = "2Gi"
    aca_min_replicas: int = 1
    aca_max_replicas: int = 1
    
    # Common
    gateway_port: int = 18789
    dry_run: bool = False
    verbose: bool = False
    
    # Internal flags
    _reuse_vnet: bool = field(default=False, init=False)
    _reuse_subnet: bool = field(default=False, init=False)
    
    def __post_init__(self):
        if not self.resource_group:
            self.resource_group = f"{self.name}-group"
        
        # Determine if reusing existing VNet/Subnet
        if self.vnet_name and self.subnet_name:
            self._reuse_vnet = True
            self._reuse_subnet = True
        elif self.vnet_name:
            self._reuse_vnet = True
    
    def get_vnet_name(self) -> str:
        return self.vnet_name or f"{self.name}-vnet"
    
    def get_subnet_name(self) -> str:
        return self.subnet_name or f"{self.name}-subnet"
    
    @property
    def nsg_name(self) -> str:
        return f"{self.name}-nsg"
    
    @property
    def pip_name(self) -> str:
        return f"{self.name}-pip"
    
    @property
    def nic_name(self) -> str:
        return f"{self.name}-nic"
    
    @property
    def vm_name(self) -> str:
        return f"{self.name}-vm"
    
    @property
    def env_name(self) -> str:
        return f"{self.name}-env"
    
    @property
    def app_name(self) -> str:
        return f"{self.name}-app"


# =============================================================================
# Azure CLI Wrapper
# =============================================================================

class AzureCLI:
    """Wrapper for Azure CLI commands."""
    
    def __init__(self, dry_run: bool = False, verbose: bool = False):
        self.dry_run = dry_run
        self.verbose = verbose
    
    def run(self, args: list[str], capture: bool = False, check: bool = True) -> Optional[str]:
        """Run an Azure CLI command."""
        cmd = ["az"] + args
        
        if self.verbose or self.dry_run:
            print(f"[{'DRY-RUN' if self.dry_run else 'RUN'}] {' '.join(cmd)}")
        
        if self.dry_run:
            return None
        
        try:
            result = subprocess.run(
                cmd,
                capture_output=capture,
                text=True,
                check=check
            )
            if capture:
                return result.stdout.strip()
            return None
        except subprocess.CalledProcessError as e:
            if check:
                print(f"Error: Command failed with exit code {e.returncode}")
                if e.stderr:
                    print(e.stderr)
                sys.exit(1)
            return None
    
    def run_json(self, args: list[str], check: bool = True) -> Optional[dict | list]:
        """Run an Azure CLI command and parse JSON output."""
        output = self.run(args + ["-o", "json"], capture=True, check=check)
        if output:
            return json.loads(output)
        return None


# =============================================================================
# VNet Address Manager
# =============================================================================

class VNetAddressManager:
    """Manage VNet address space allocation."""
    
    BASE_NETWORK = "10.200.0.0/16"  # Base range for all VNets
    VNET_PREFIX_LEN = 27  # /27 = 32 addresses per VNet
    SUBNET_PREFIX_LEN = 28  # /28 = 16 addresses per subnet
    
    def __init__(self, az: AzureCLI, resource_group: str):
        self.az = az
        self.resource_group = resource_group
    
    def get_existing_vnet_prefixes(self) -> list[str]:
        """Get all existing VNet address prefixes in the resource group."""
        if self.az.dry_run:
            return []
        
        result = self.az.run_json([
            "network", "vnet", "list",
            "--resource-group", self.resource_group,
            "--query", "[].addressSpace.addressPrefixes[]"
        ], check=False)
        
        if result and isinstance(result, list):
            return result
        return []
    
    def get_next_available_prefix(self) -> tuple[str, str]:
        """
        Find the next available /27 VNet prefix and /28 subnet prefix.
        Returns (vnet_prefix, subnet_prefix).
        """
        existing_prefixes = self.get_existing_vnet_prefixes()
        
        # Parse existing networks
        existing_networks = []
        for prefix in existing_prefixes:
            try:
                existing_networks.append(ipaddress.ip_network(prefix))
            except ValueError:
                pass
        
        # Iterate through possible /27 blocks in 10.200.0.0/16
        base_network = ipaddress.ip_network(self.BASE_NETWORK)
        
        for subnet in base_network.subnets(new_prefix=self.VNET_PREFIX_LEN):
            # Check if this subnet overlaps with any existing
            overlaps = False
            for existing in existing_networks:
                if subnet.overlaps(existing):
                    overlaps = True
                    break
            
            if not overlaps:
                vnet_prefix = str(subnet)
                # First /28 within the /27
                subnet_network = list(subnet.subnets(new_prefix=self.SUBNET_PREFIX_LEN))[0]
                subnet_prefix = str(subnet_network)
                return vnet_prefix, subnet_prefix
        
        raise RuntimeError("No available VNet address space in 10.200.0.0/16")
    
    def get_next_subnet_in_vnet(self, vnet_name: str) -> str:
        """Find the next available /28 subnet within an existing VNet."""
        if self.az.dry_run:
            return "10.200.0.16/28"  # Dummy for dry run
        
        # Get VNet info
        vnet_info = self.az.run_json([
            "network", "vnet", "show",
            "--resource-group", self.resource_group,
            "--name", vnet_name
        ], check=False)
        
        if not vnet_info:
            raise RuntimeError(f"VNet '{vnet_name}' not found in resource group '{self.resource_group}'")
        
        # Get VNet address space
        vnet_prefixes = vnet_info.get("addressSpace", {}).get("addressPrefixes", [])
        if not vnet_prefixes:
            raise RuntimeError(f"VNet '{vnet_name}' has no address space")
        
        vnet_network = ipaddress.ip_network(vnet_prefixes[0])
        
        # Get existing subnets
        existing_subnets = []
        for subnet in vnet_info.get("subnets", []):
            prefix = subnet.get("addressPrefix")
            if prefix:
                existing_subnets.append(ipaddress.ip_network(prefix))
        
        # Find next available /28
        for subnet in vnet_network.subnets(new_prefix=self.SUBNET_PREFIX_LEN):
            overlaps = False
            for existing in existing_subnets:
                if subnet.overlaps(existing):
                    overlaps = True
                    break
            
            if not overlaps:
                return str(subnet)
        
        raise RuntimeError(f"No available subnet space in VNet '{vnet_name}'")


# =============================================================================
# VM Deployer
# =============================================================================

class VMDeployer:
    """Deploy OpenClaw to an Azure VM."""
    
    INSTALL_SCRIPT = '''#!/bin/bash
set -euo pipefail

echo "==> Updating system..."
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

echo "==> Installing Node.js 22.x..."
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt-get install -y nodejs

echo "==> Installing OpenClaw..."
npm install -g openclaw

echo "==> Creating openclaw user..."
useradd -m -s /bin/bash openclaw || true

echo "==> Setting up workspace..."
mkdir -p /data/workspace
chown openclaw:openclaw /data/workspace

echo "==> Configuring OpenClaw..."
mkdir -p /home/openclaw/.openclaw
TOKEN=$(openssl rand -hex 24)

cat > /home/openclaw/.openclaw/openclaw.json << EOFCONFIG
{
  "gateway": {
    "mode": "local",
    "bind": "lan",
    "port": 18789,
    "auth": {
      "mode": "token",
      "token": "$TOKEN"
    }
  },
  "agents": {
    "defaults": {
      "workspace": "/data/workspace",
      "model": {
        "primary": "github-copilot/claude-haiku-4.5"
      }
    }
  },
  "browser": {
    "enabled": true,
    "headless": true,
    "noSandbox": true
  }
}
EOFCONFIG

chown -R openclaw:openclaw /home/openclaw/.openclaw

echo "==> Creating systemd service..."
cat > /etc/systemd/system/openclaw.service << 'EOFSVC'
[Unit]
Description=OpenClaw Gateway
After=network.target

[Service]
Type=simple
User=openclaw
WorkingDirectory=/data/workspace
ExecStart=/usr/bin/openclaw gateway start --foreground
Restart=on-failure
RestartSec=10
Environment=HOME=/home/openclaw
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
EOFSVC

echo "==> Starting OpenClaw service..."
systemctl daemon-reload
systemctl enable openclaw
systemctl start openclaw

echo "==> Installation complete!"
echo "TOKEN=$TOKEN"
'''

    def __init__(self, config: DeployConfig):
        self.config = config
        self.az = AzureCLI(dry_run=config.dry_run, verbose=config.verbose)
        self.vnet_manager = VNetAddressManager(self.az, config.resource_group)
    
    def deploy(self) -> dict:
        """Deploy the VM and install OpenClaw."""
        # Ensure resource group exists first (needed for VNet queries)
        self._create_resource_group()
        
        # Resolve VNet/Subnet configuration
        self._resolve_network_config()
        
        print(f"==> Deploying OpenClaw to Azure VM")
        print(f"    Name:           {self.config.name}")
        print(f"    Location:       {self.config.location}")
        print(f"    Resource Group: {self.config.resource_group}")
        print(f"    VM Size:        {self.config.vm_size}")
        print(f"    Spot:           {self.config.use_spot}")
        print(f"    VNet:           {self.config.get_vnet_name()} ({self.config.vnet_prefix}){' [existing]' if self.config._reuse_vnet else ''}")
        print(f"    Subnet:         {self.config.get_subnet_name()} ({self.config.subnet_prefix}){' [existing]' if self.config._reuse_subnet else ''}")
        print()
        
        # Validate SSH key
        if not self.config.dry_run:
            ssh_key = Path(self.config.ssh_key_path)
            if not ssh_key.exists():
                print(f"Error: SSH key not found at {self.config.ssh_key_path}")
                sys.exit(1)
        
        # Create network resources (skip if reusing)
        if not self.config._reuse_vnet:
            self._create_vnet()
        
        if not self.config._reuse_subnet:
            self._create_subnet()
        
        # Create remaining resources
        self._create_nsg()
        self._create_nsg_rules()
        self._create_public_ip()
        self._create_nic()
        self._create_vm()
        
        # Get public IP
        public_ip = self._get_public_ip()
        
        # Install OpenClaw
        if not self.config.dry_run and public_ip:
            token = self._install_openclaw(public_ip)
        else:
            token = "<generated-on-install>"
            public_ip = public_ip or "<public-ip>"
        
        result = {
            "target": "vm",
            "vm_name": self.config.vm_name,
            "resource_group": self.config.resource_group,
            "location": self.config.location,
            "vnet_name": self.config.get_vnet_name(),
            "vnet_prefix": self.config.vnet_prefix,
            "subnet_name": self.config.get_subnet_name(),
            "subnet_prefix": self.config.subnet_prefix,
            "public_ip": public_ip,
            "ssh_command": f"ssh {self.config.admin_username}@{public_ip}",
            "token": token,
            "dashboard_url": f"http://{public_ip}:{self.config.gateway_port}/?token={token}",
        }
        
        self._print_summary(result)
        return result
    
    def _resolve_network_config(self):
        """Resolve VNet and subnet configuration."""
        if self.config._reuse_vnet and self.config._reuse_subnet:
            # Both specified - validate they exist
            print(f"==> Using existing VNet: {self.config.vnet_name}")
            print(f"==> Using existing subnet: {self.config.subnet_name}")
            # Get subnet prefix for display
            if not self.config.dry_run:
                subnet_info = self.az.run_json([
                    "network", "vnet", "subnet", "show",
                    "--resource-group", self.config.resource_group,
                    "--vnet-name", self.config.vnet_name,
                    "--name", self.config.subnet_name
                ], check=False)
                if subnet_info:
                    self.config.subnet_prefix = subnet_info.get("addressPrefix", "existing")
                    # Get VNet prefix too
                    vnet_info = self.az.run_json([
                        "network", "vnet", "show",
                        "--resource-group", self.config.resource_group,
                        "--name", self.config.vnet_name
                    ], check=False)
                    if vnet_info:
                        prefixes = vnet_info.get("addressSpace", {}).get("addressPrefixes", [])
                        self.config.vnet_prefix = prefixes[0] if prefixes else "existing"
        
        elif self.config._reuse_vnet:
            # Reuse VNet, create new subnet
            print(f"==> Using existing VNet: {self.config.vnet_name}")
            print(f"==> Finding next available subnet...")
            self.config.subnet_prefix = self.vnet_manager.get_next_subnet_in_vnet(self.config.vnet_name)
            # Get VNet prefix for display
            if not self.config.dry_run:
                vnet_info = self.az.run_json([
                    "network", "vnet", "show",
                    "--resource-group", self.config.resource_group,
                    "--name", self.config.vnet_name
                ], check=False)
                if vnet_info:
                    prefixes = vnet_info.get("addressSpace", {}).get("addressPrefixes", [])
                    self.config.vnet_prefix = prefixes[0] if prefixes else "existing"
        
        else:
            # Create new VNet and subnet
            if not self.config.vnet_prefix:
                print(f"==> Finding next available VNet address space...")
                self.config.vnet_prefix, self.config.subnet_prefix = \
                    self.vnet_manager.get_next_available_prefix()
            elif not self.config.subnet_prefix:
                # VNet prefix specified but not subnet - derive subnet
                vnet_network = ipaddress.ip_network(self.config.vnet_prefix)
                subnet_network = list(vnet_network.subnets(new_prefix=28))[0]
                self.config.subnet_prefix = str(subnet_network)
    
    def _create_resource_group(self):
        print(f"==> Creating/verifying resource group: {self.config.resource_group}")
        self.az.run([
            "group", "create",
            "--name", self.config.resource_group,
            "--location", self.config.location,
            "--output", "none"
        ], check=False)
    
    def _create_vnet(self):
        print(f"==> Creating VNet: {self.config.get_vnet_name()} ({self.config.vnet_prefix})")
        self.az.run([
            "network", "vnet", "create",
            "--resource-group", self.config.resource_group,
            "--name", self.config.get_vnet_name(),
            "--address-prefix", self.config.vnet_prefix,
            "--location", self.config.location,
            "--output", "none"
        ])
    
    def _create_subnet(self):
        print(f"==> Creating subnet: {self.config.get_subnet_name()} ({self.config.subnet_prefix})")
        self.az.run([
            "network", "vnet", "subnet", "create",
            "--resource-group", self.config.resource_group,
            "--vnet-name", self.config.get_vnet_name(),
            "--name", self.config.get_subnet_name(),
            "--address-prefix", self.config.subnet_prefix,
            "--output", "none"
        ])
    
    def _create_nsg(self):
        print(f"==> Creating NSG: {self.config.nsg_name}")
        self.az.run([
            "network", "nsg", "create",
            "--resource-group", self.config.resource_group,
            "--name", self.config.nsg_name,
            "--location", self.config.location,
            "--output", "none"
        ])
    
    def _create_nsg_rules(self):
        print("==> Adding NSG rules (SSH, OpenClaw)")
        # SSH
        self.az.run([
            "network", "nsg", "rule", "create",
            "--resource-group", self.config.resource_group,
            "--nsg-name", self.config.nsg_name,
            "--name", "AllowSSH",
            "--priority", "1000",
            "--access", "Allow",
            "--direction", "Inbound",
            "--protocol", "Tcp",
            "--destination-port-ranges", "22",
            "--output", "none"
        ])
        # OpenClaw gateway
        self.az.run([
            "network", "nsg", "rule", "create",
            "--resource-group", self.config.resource_group,
            "--nsg-name", self.config.nsg_name,
            "--name", "AllowOpenClaw",
            "--priority", "1010",
            "--access", "Allow",
            "--direction", "Inbound",
            "--protocol", "Tcp",
            "--destination-port-ranges", str(self.config.gateway_port),
            "--output", "none"
        ])
    
    def _create_public_ip(self):
        print(f"==> Creating public IP: {self.config.pip_name}")
        self.az.run([
            "network", "public-ip", "create",
            "--resource-group", self.config.resource_group,
            "--name", self.config.pip_name,
            "--location", self.config.location,
            "--sku", "Standard",
            "--allocation-method", "Static",
            "--output", "none"
        ])
    
    def _create_nic(self):
        print(f"==> Creating NIC: {self.config.nic_name}")
        self.az.run([
            "network", "nic", "create",
            "--resource-group", self.config.resource_group,
            "--name", self.config.nic_name,
            "--location", self.config.location,
            "--vnet-name", self.config.get_vnet_name(),
            "--subnet", self.config.get_subnet_name(),
            "--network-security-group", self.config.nsg_name,
            "--public-ip-address", self.config.pip_name,
            "--output", "none"
        ])
    
    def _create_vm(self):
        print(f"==> Creating VM: {self.config.vm_name}")
        cmd = [
            "vm", "create",
            "--resource-group", self.config.resource_group,
            "--name", self.config.vm_name,
            "--location", self.config.location,
            "--nics", self.config.nic_name,
            "--image", self.config.os_image,
            "--size", self.config.vm_size,
            "--admin-username", self.config.admin_username,
            "--ssh-key-value", self.config.ssh_key_path,
            "--assign-identity",
            "--output", "none"
        ]
        
        if self.config.use_spot:
            cmd.extend([
                "--priority", "Spot",
                "--eviction-policy", "Deallocate",
                "--max-price", "-1"
            ])
        
        self.az.run(cmd)
    
    def _get_public_ip(self) -> Optional[str]:
        if self.config.dry_run:
            return None
        
        print("==> Retrieving public IP...")
        result = self.az.run_json([
            "network", "public-ip", "show",
            "--resource-group", self.config.resource_group,
            "--name", self.config.pip_name,
            "--query", "ipAddress"
        ])
        return result if isinstance(result, str) else None
    
    def _install_openclaw(self, public_ip: str) -> str:
        """SSH into the VM and install OpenClaw."""
        print("==> Installing OpenClaw on VM (this may take a few minutes)...")
        
        # Wait for SSH to be ready
        import time
        for attempt in range(30):
            try:
                result = subprocess.run(
                    ["ssh", "-o", "StrictHostKeyChecking=no", "-o", "ConnectTimeout=5",
                     f"{self.config.admin_username}@{public_ip}", "echo ready"],
                    capture_output=True, text=True, timeout=10
                )
                if result.returncode == 0:
                    break
            except (subprocess.TimeoutExpired, subprocess.SubprocessError):
                pass
            print(f"    Waiting for SSH... ({attempt + 1}/30)")
            time.sleep(10)
        
        # Run install script
        result = subprocess.run(
            ["ssh", "-o", "StrictHostKeyChecking=no",
             f"{self.config.admin_username}@{public_ip}",
             f"sudo bash -c '{self.INSTALL_SCRIPT}'"],
            capture_output=True, text=True
        )
        
        if result.returncode != 0:
            print(f"Warning: Installation may have failed: {result.stderr}")
        
        # Extract token from output
        token = ""
        for line in result.stdout.split("\n"):
            if line.startswith("TOKEN="):
                token = line.split("=", 1)[1]
                break
        
        return token
    
    def _print_summary(self, result: dict):
        print()
        print("=" * 50)
        print("Deployment Complete!")
        print("=" * 50)
        print(f"  VM:           {result['vm_name']}")
        print(f"  Public IP:    {result['public_ip']}")
        print(f"  SSH:          {result['ssh_command']}")
        print(f"  VNet:         {result['vnet_name']} ({result['vnet_prefix']})")
        print(f"  Subnet:       {result['subnet_name']} ({result['subnet_prefix']})")
        print()
        print(f"  Dashboard:    {result['dashboard_url']}")
        print()


# =============================================================================
# ACA Deployer
# =============================================================================

class ACADeployer:
    """Deploy OpenClaw to Azure Container Apps."""
    
    def __init__(self, config: DeployConfig):
        self.config = config
        self.az = AzureCLI(dry_run=config.dry_run, verbose=config.verbose)
    
    def deploy(self) -> dict:
        """Deploy OpenClaw to Azure Container Apps."""
        print(f"==> Deploying OpenClaw to Azure Container Apps")
        print(f"    Name:           {self.config.name}")
        print(f"    Location:       {self.config.location}")
        print(f"    Resource Group: {self.config.resource_group}")
        print()
        
        # Generate token
        token = secrets.token_hex(24)
        
        # Create resources
        self._create_resource_group()
        self._create_environment()
        self._create_container_app(token)
        
        # Get FQDN
        fqdn = self._get_fqdn()
        
        result = {
            "target": "aca",
            "app_name": self.config.app_name,
            "resource_group": self.config.resource_group,
            "location": self.config.location,
            "fqdn": fqdn or "<fqdn>",
            "token": token,
            "dashboard_url": f"https://{fqdn}/?token={token}" if fqdn else "<pending>",
        }
        
        self._print_summary(result)
        return result
    
    def _create_resource_group(self):
        print(f"==> Creating resource group: {self.config.resource_group}")
        self.az.run([
            "group", "create",
            "--name", self.config.resource_group,
            "--location", self.config.location,
            "--output", "none"
        ], check=False)
    
    def _create_environment(self):
        print(f"==> Creating Container Apps Environment: {self.config.env_name}")
        self.az.run([
            "containerapp", "env", "create",
            "--name", self.config.env_name,
            "--resource-group", self.config.resource_group,
            "--location", self.config.location,
            "--output", "none"
        ])
    
    def _create_container_app(self, token: str):
        print(f"==> Creating Container App: {self.config.app_name}")
        self.az.run([
            "containerapp", "create",
            "--name", self.config.app_name,
            "--resource-group", self.config.resource_group,
            "--environment", self.config.env_name,
            "--image", "node:22-slim",
            "--target-port", str(self.config.gateway_port),
            "--ingress", "external",
            "--min-replicas", str(self.config.aca_min_replicas),
            "--max-replicas", str(self.config.aca_max_replicas),
            "--cpu", str(self.config.aca_cpu),
            "--memory", self.config.aca_memory,
            "--env-vars", f"OPENCLAW_GATEWAY_TOKEN={token}",
            "--command", "sh", "-c", "npm install -g openclaw && openclaw gateway start --foreground",
            "--output", "none"
        ])
    
    def _get_fqdn(self) -> Optional[str]:
        if self.config.dry_run:
            return None
        
        print("==> Retrieving FQDN...")
        result = self.az.run_json([
            "containerapp", "show",
            "--name", self.config.app_name,
            "--resource-group", self.config.resource_group,
            "--query", "properties.configuration.ingress.fqdn"
        ])
        return result if isinstance(result, str) else None
    
    def _print_summary(self, result: dict):
        print()
        print("=" * 50)
        print("Deployment Complete!")
        print("=" * 50)
        print(f"  App:        {result['app_name']}")
        print(f"  FQDN:       {result['fqdn']}")
        print()
        print(f"  Dashboard:  {result['dashboard_url']}")
        print()
        print("  Note: HTTPS is handled by Azure Container Apps ingress.")
        print()


# =============================================================================
# CLI
# =============================================================================

def parse_args() -> DeployConfig:
    """Parse command line arguments."""
    parser = argparse.ArgumentParser(
        description="Deploy OpenClaw to Azure Container Apps or Azure VM",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__
    )
    
    subparsers = parser.add_subparsers(dest="target", required=True, help="Deployment target")
    
    # Common arguments
    def add_common_args(p):
        p.add_argument("--name", required=True, help="Deployment name (used for RG, VM, etc.)")
        p.add_argument("--location", required=True, help="Azure region (e.g., westus2)")
        p.add_argument("--resource-group", help="Existing RG to reuse (default: <name>-group)")
        p.add_argument("--dry-run", action="store_true", help="Show commands without executing")
        p.add_argument("--verbose", "-v", action="store_true", help="Verbose output")
    
    # VM subcommand
    vm_parser = subparsers.add_parser("vm", help="Deploy to Azure VM")
    add_common_args(vm_parser)
    vm_parser.add_argument("--spot", dest="use_spot", action="store_true", default=True,
                          help="Use spot VM pricing (default)")
    vm_parser.add_argument("--no-spot", dest="use_spot", action="store_false",
                          help="Use regular VM pricing")
    vm_parser.add_argument("--vm-size", default="Standard_D2als_v6",
                          help="VM size (default: Standard_D2als_v6)")
    vm_parser.add_argument("--vnet-name", help="Existing VNet name to reuse")
    vm_parser.add_argument("--subnet-name", help="Existing subnet name to reuse (requires --vnet-name)")
    vm_parser.add_argument("--vnet-prefix", default="",
                          help="VNet address prefix (default: auto-increment in 10.200.x.x/27)")
    vm_parser.add_argument("--subnet-prefix", default="",
                          help="Subnet address prefix (default: auto-calculated)")
    vm_parser.add_argument("--ssh-key", dest="ssh_key_path",
                          default=str(Path.home() / ".ssh" / "id_rsa.pub"),
                          help="Path to SSH public key")
    vm_parser.add_argument("--admin-username", default="azureuser",
                          help="VM admin username (default: azureuser)")
    
    # ACA subcommand
    aca_parser = subparsers.add_parser("aca", help="Deploy to Azure Container Apps")
    add_common_args(aca_parser)
    aca_parser.add_argument("--cpu", dest="aca_cpu", type=float, default=1.0,
                           help="CPU cores (default: 1.0)")
    aca_parser.add_argument("--memory", dest="aca_memory", default="2Gi",
                           help="Memory (default: 2Gi)")
    aca_parser.add_argument("--min-replicas", dest="aca_min_replicas", type=int, default=1,
                           help="Minimum replicas (default: 1)")
    aca_parser.add_argument("--max-replicas", dest="aca_max_replicas", type=int, default=1,
                           help="Maximum replicas (default: 1)")
    
    args = parser.parse_args()
    
    # Validate VM args
    if args.target == "vm":
        if args.subnet_name and not args.vnet_name:
            parser.error("--subnet-name requires --vnet-name")
    
    # Convert to DeployConfig
    config_kwargs = {
        "target": args.target,
        "name": args.name,
        "location": args.location,
        "resource_group": args.resource_group,
        "dry_run": args.dry_run,
        "verbose": args.verbose,
    }
    
    if args.target == "vm":
        config_kwargs.update({
            "use_spot": args.use_spot,
            "vm_size": args.vm_size,
            "vnet_name": args.vnet_name,
            "subnet_name": args.subnet_name,
            "vnet_prefix": args.vnet_prefix,
            "subnet_prefix": args.subnet_prefix,
            "ssh_key_path": args.ssh_key_path,
            "admin_username": args.admin_username,
        })
    elif args.target == "aca":
        config_kwargs.update({
            "aca_cpu": args.aca_cpu,
            "aca_memory": args.aca_memory,
            "aca_min_replicas": args.aca_min_replicas,
            "aca_max_replicas": args.aca_max_replicas,
        })
    
    return DeployConfig(**config_kwargs)


def main():
    """Main entry point."""
    config = parse_args()
    
    if config.target == "vm":
        deployer = VMDeployer(config)
    elif config.target == "aca":
        deployer = ACADeployer(config)
    else:
        print(f"Error: Unknown target '{config.target}'")
        sys.exit(1)
    
    result = deployer.deploy()
    
    # Output result as JSON for scripting
    if config.verbose:
        print("\nResult JSON:")
        print(json.dumps(result, indent=2))
    
    print("\n==> Done!")


if __name__ == "__main__":
    main()
