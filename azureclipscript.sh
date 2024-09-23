# Variables (unchanged)
$resourceGroup = "Azure_script"
$location = "North Europe"
$vnetName = "Script_VNet"
$webSubnetName = "webSubnet"
$appSubnetName = "appSubnet"
$dataSubnetName = "dataSubnet"
$webVMSize = "Standard_B1s"
$appVMSize = "Standard_B1s"
$webVMCount = 2
$appVMCount = 2
$sqlServerName = "scriptsqlserver" + (Get-Random -Minimum 1000 -Maximum 9999)
$sqlDatabaseName = "mySqlDatabase"
$sqlAdminUser = "sqladmin"
$sqlAdminPassword = "Studiegruppe#3"
$failoverLocation = "Sweden Central"

# Create Resource Group (unchanged)
New-AzResourceGroup -Name $resourceGroup -Location $location

# Create Virtual Network with 3 subnets (unchanged)
$vnet = New-AzVirtualNetwork -ResourceGroupName $resourceGroup -Location $location -Name $vnetName -AddressPrefix 10.0.0.0/16
Add-AzVirtualNetworkSubnetConfig -Name $webSubnetName -AddressPrefix 10.0.1.0/24 -VirtualNetwork $vnet
Add-AzVirtualNetworkSubnetConfig -Name $appSubnetName -AddressPrefix 10.0.2.0/24 -VirtualNetwork $vnet
Add-AzVirtualNetworkSubnetConfig -Name $dataSubnetName -AddressPrefix 10.0.3.0/24 -VirtualNetwork $vnet
# Apply the changes
$vnet | Set-AzVirtualNetwork

# Retrieve updated VNet with subnet IDs (unchanged)
$vnet = Get-AzVirtualNetwork -Name $vnetName -ResourceGroupName $resourceGroup
$webSubnetId = ($vnet.Subnets | Where-Object { $_.Name -eq $webSubnetName }).Id
$appSubnetId = ($vnet.Subnets | Where-Object { $_.Name -eq $appSubnetName }).Id
# WEB TIER

# Step 1: Create Public IP for External Load Balancer
$publicIP = New-AzPublicIpAddress -ResourceGroupName $resourceGroup -Location $location `
   -Name "webPublicIP" -AllocationMethod Static -Sku Standard

# Step 2: Create External Load Balancer for Web Tier
$webFrontendIP = New-AzLoadBalancerFrontendIpConfig -Name "webFrontEnd" -PublicIpAddress $publicIP

$webBackendPool = New-AzLoadBalancerBackendAddressPoolConfig -Name "webBackEndPool"

$webProbe = New-AzLoadBalancerProbeConfig -Name "webHealthProbe" -Protocol Tcp -Port 80 -IntervalInSeconds 15 -ProbeCount 2

$webLbRule = New-AzLoadBalancerRuleConfig -Name "webLoadBalancingRule" -FrontendIpConfiguration $webFrontendIP `
  -BackendAddressPool $webBackendPool -Protocol Tcp -FrontendPort 80 -BackendPort 80

$webLoadBalancer = New-AzLoadBalancer -ResourceGroupName $resourceGroup -Location $location `
  -Name "webExternalLB" -FrontendIpConfiguration $webFrontendIP -BackendAddressPool $webBackendPool `
  -LoadBalancingRule $webLbRule

# Step 3: Create VMs for Web Tier
for ($i=1; $i -le $webVMCount; $i++) {
    # Create Network Interface for the Web VM
    $webNic = New-AzNetworkInterface -Name "webNIC$i" -ResourceGroupName $resourceGroup -Location $location `
      -SubnetId $webSubnetId -LoadBalancerBackendAddressPoolId $webLoadBalancer.BackendAddressPools[0].Id 

    # Initialize the VM Config
    $webVM = New-AzVMConfig -VMName "webVM$i" -VMSize $webVMSize

    # Set OS for the VM
    $webVM = Set-AzVMOperatingSystem -VM $webVM -Linux -ComputerName "webVM$i" -Credential (Get-Credential -Message "Enter VM credentials")

    # Set the source image (Ubuntu 18.04)
    $webVM = Set-AzVMSourceImage -VM $webVM -PublisherName "Canonical" -Offer "UbuntuServer" -Skus "18.04-LTS" -Version "latest"

    # Add the Network Interface to the VM
    $webVM = Add-AzVMNetworkInterface -VM $webVM -Id $webNic.Id

    # Deploy the VM
    New-AzVM -ResourceGroupName $resourceGroup -Location $location -VM $webVM
}
# Internal Load Balancer Configuration (App Tier)
$internalFrontendIP = New-AzLoadBalancerFrontendIpConfig -Name "appFrontEnd" -PrivateIpAddress "10.0.2.4" `
  -SubnetId $appSubnetId

$internalBackendPool = New-AzLoadBalancerBackendAddressPoolConfig -Name "appBackEndPool"
$appProbe = New-AzLoadBalancerProbeConfig -Name "appHealthProbe" -Protocol Tcp -Port 8080 -IntervalInSeconds 15 -ProbeCount 2
$appLbRule = New-AzLoadBalancerRuleConfig -Name "appLoadBalancingRule" -FrontendIpConfiguration $internalFrontendIP `
  -BackendAddressPool $internalBackendPool -Probe $appProbe -Protocol Tcp -FrontendPort 8080 -BackendPort 8080

$appLoadBalancer = New-AzLoadBalancer -ResourceGroupName $resourceGroup -Location $location `
  -Name "appInternalLB" -FrontendIpConfiguration $internalFrontendIP -BackendAddressPool $internalBackendPool `
  -Probe $appProbe -LoadBalancingRule $appLbRule

# App Tier: Create VMs for App Tier
for ($i=1; $i -le $appVMCount; $i++) {
    # Create Network Interface for the App VM
    $appNic = New-AzNetworkInterface -Name "appNIC$i" -ResourceGroupName $resourceGroup -Location $location `
      -SubnetId $appSubnetId -LoadBalancerBackendAddressPoolId $appLoadBalancer.BackendAddressPools[0].Id 

    # Initialize the VM Config
    $appVM = New-AzVMConfig -VMName "appVM$i" -VMSize $appVMSize

    # Set OS for the VM
    $appVM = Set-AzVMOperatingSystem -VM $appVM -Linux -ComputerName "appVM$i" -Credential (Get-Credential -Message "Enter VM credentials")

    # Set the source image (Ubuntu 18.04)
    $appVM = Set-AzVMSourceImage -VM $appVM -PublisherName "Canonical" -Offer "UbuntuServer" -Skus "18.04-LTS" -Version "latest"

    # Add the Network Interface to the VM
    $appVM = Add-AzVMNetworkInterface -VM $appVM -Id $appNic.Id

    # Deploy the VM
    New-AzVM -ResourceGroupName $resourceGroup -Location $location -VM $appVM
}

# DATA TIER: Create SQL Server and SQL Database
$sqlServer = New-AzSqlServer -ResourceGroupName $resourceGroup -Location $location -ServerName $sqlServerName `
  -SqlAdministratorCredentials (New-Object -TypeName PSCredential -ArgumentList $sqlAdminUser, (ConvertTo-SecureString -String $sqlAdminPassword -AsPlainText -Force))

New-AzSqlDatabase -ResourceGroupName $resourceGroup -ServerName $sqlServerName -DatabaseName $sqlDatabaseName `
  -RequestedServiceObjectiveName "S0"
