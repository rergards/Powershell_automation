<#
.SYNOPSIS
    This script migrates VMs from one vCenter to another and updates Horizon server configurations.

.DESCRIPTION
    MainMigrationScript.ps1 performs a batch migration of VMs based on a CSV file input. 
    It handles the migration process on VMware vCenter servers and updates VM configurations on a Horizon server.
    It uses VMotion for seamless migration.
    It requires VMware PowerCLI and a specific module for Horizon integration.
    migration_list.csv contains the following columns:
    - ComputerName
    - DistinguishedName
    - SamAccountName

    Update the configuration variables as needed for your environment.

.EXAMPLE
    .\MainMigrationScript.ps1

.NOTES
    Author: https://github.com/rergards/
    Version: 1.0
    Date: 2023-12-04

    ToDo: Add better error handling, add parallelism, add idempotency to horizon migration, add logging

#>

# Cleanup of all variables in current session
Get-Variable | ForEach-Object { Remove-Variable -Name $_.Name -ErrorAction SilentlyContinue }

# Ignore invalid or self-signed certificates
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false

# Configuration Variables
$sourceVCenter = 'source-vcenter.example.com'
$destVCenter = 'destination-vcenter.example.com'
$csvFilePath = "path\to\your\migration_list.csv"
$batchSize = 16  # Adjustable batch processing size.
$destinationFolder = "DestinationFolderName"
$DestinationDatastoreName = "DatastoreName"
$vdSwitchName = 'VirtualDistributedSwitchName'

# Horizon specific variables
$horizonServer = 'horizon-server.example.com'
$initialHorizonGroup = "InitialHorizonGroup"
$targetHorizonGroup = "TargetHorizonGroup"
$horizonPoolName = "HorizonPoolName"
$verboseDebug = $false

# Import VMware PowerCLI module
Import-Module VMware.PowerCLI

# Import horizon migration module and CrossVCenterMigrationModule
. ".\MigrateHorizonPoolBatchModule.ps1"

# Connect to Source and Destination vCenter Servers and Horizon Server
try {
    Connect-VIServer -Server $sourceVCenter -ErrorAction Stop
    Connect-VIServer -Server $destVCenter -ErrorAction Stop
    Connect-HVServer -Server $horizonServer -ErrorAction Stop
} catch {
    Write-Host "Error connecting to server: $_"
    exit
}

# Import VM list from CSV
$vmList = Import-Csv -Path $csvFilePath

# Split VM list into batches
$batches = [System.Collections.ArrayList]@()
for ($i = 0; $i -lt $vmList.Count; $i += $batchSize) {
    $batches.Add($vmList[$i..($i + $batchSize - 1)])
}

# VM Migration Process
foreach ($batch in $batches) {
    try {
        # Initiate VM Migration
        # Retrieve all destination hosts just once before the loop
        Write-Host "Destination Datastore Name: $DestinationDatastoreName"
        $destinationDatastore = Get-Datastore -Server $destVCenter -Name $DestinationDatastoreName
        Write-Host "Destination Datastore: $destinationDatastore"

        $allDestinationHosts = Get-VMHost -Server $destVCenter | Where-Object {
            $_ | Get-Datastore | Where-Object { $_.Id -eq $destinationDatastore.Id }
        }
        Write-Host "All Destination Hosts: $allDestinationHosts"

        # Keep track of the next host index
        $nextHostIndex = 0

        foreach ($vm in $batch) {
            $vmToMigrate = Get-VM -Name $vm.ComputerName -Server $sourceVCenter
            $destinationDatastore = Get-Datastore -Server $destVCenter -Name $DestinationDatastoreName
            # Select the next host in a round-robin fashion
            $destinationHost = $allDestinationHosts[$nextHostIndex]
            # Increment the index for the next iteration, wrap around if it reaches the end of the list
            $nextHostIndex = ($nextHostIndex + 1) % $allDestinationHosts.Count
            $destinationFolder = Get-Folder -Name $destinationFolder -Server $destVCenter
            $networkAdapter = Get-NetworkAdapter -VM $vmToMigrate
            $destinationPortGroup = Get-VDPortgroup -VDSwitch $vdSwitchName -Name $networkAdapter.NetworkName -Server $destVCenter
            Write-Host "Destination host $destinationHost"
            # Perform the migration with network mapping
            Move-VM -VM $vmToMigrate -Destination $destinationHost -Datastore $destinationDatastore -InventoryLocation $destinationFolder -NetworkAdapter $networkAdapter -PortGroup $destinationPortGroup -Confirm:$false -RunAsync
        }


        # Monitor Migration Tasks
        Write-Host "Waiting for migration tasks on target VCenter for 2 minutes"
        Start-Sleep -Seconds 120
        # Configuration for VM monitoring
        $CheckIntervalSeconds = 120  # Interval for checking VMs
        $allVMsMigrated = $false

        Write-Host "Starting continuous monitoring for VM migration status, renewing every 2 minutes to avoid visual clutter"
        while (-not $allVMsMigrated) {
            try {
                $allVMsMigrated = $true  # Assume all VMs are migrated, will be set to false if any VM is still in progress
                Write-Host "----------------------------------"
                foreach ($vmName in $batch.ComputerName) {
                    $migratedVM = Get-VM -Name $vmName -Server $destVCenter -ErrorAction SilentlyContinue
                    
                    if ($migratedVM -and $migratedVM.Folder.Name -eq $destinationFolder.Name) {
                        Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): Migration completed for VM: $vmName"
                    } else {
                        Write-Host "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss'): Migration in progress for VM: $vmName"
                        $allVMsMigrated = $false
                    }
                }
            } catch {
                Write-Host "Error encountered during VM migration monitoring: $_"
            }

            if (-not $allVMsMigrated) {
                Start-Sleep -Seconds $CheckIntervalSeconds
            }
        }

        # Post-migration verification    
        foreach ($vm in $batch) {        
            $vmName = $vm.ComputerName
            $migratedVM = Get-VM -Name $vmName -Server $destVCenter
            if ($migratedVM -and $migratedVM.Folder.Name -eq $destinationFolder.Name) {
                Write-Host "Final verification: Migration successful for VM: $vmName"
            } else {
                Write-Host "Final verification: Migration failed or VM not in correct folder/vCenter for VM: $vmName"
                Read-Host "Press Enter to continue or CTRL+C to stop."
            }
        }

    MigrateHorizonPool -Batch $batch -TargetGroup $targetHorizonGroup -InitialGroup $initialHorizonGroup -HorizonPoolName $horizonPoolName -DestVCenter $destVCenter -VerboseDebug $verboseDebug
    } catch {
        Write-Host "Error encountered during migration of VM: $vmName. Error: $_"
        Read-Host "Press Enter to continue or CTRL+C to stop."
    }
Write-Host "It was batch of:"
$batch
}
