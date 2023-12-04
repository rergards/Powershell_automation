<#
.SYNOPSIS
    Handles the migration of Horizon pools in batches.

.DESCRIPTION
    MigrateHorizonPoolBatchModule.ps1 contains a function for migrating Horizon pools. 
    It moves users between AD groups, removes VMs from the Horizon pool, and re-adds them after migration.
    Requires Horizon and Active Directory modules.

    Update the function parameters with appropriate values for your environment.

.EXAMPLE
    Import-Module .\MigrateHorizonPoolBatchModule.ps1
    MigrateHorizonPool -Batch $batch -TargetGroup "TargetADGroup" -InitialGroup "InitialADGroup" -HorizonPoolName "YourHorizonPoolName" -DestVCenter "destination-vcenter.example.com"

.NOTES
    Author: https://github.com/rergards/
    Version: 1.0
    Date: 2023-12-04

    ToDo: Make some parameters non-Mandatory
    
#>

function MigrateHorizonPool {
    param(
        [Parameter(Mandatory = $true)]
        [array]$Batch,

        [Parameter(Mandatory = $true)]
        [string]$TargetGroup,

        [Parameter(Mandatory = $true)]
        [string]$InitialGroup,

        [Parameter(Mandatory = $true)]
        [string]$HorizonPoolName,

        [Parameter(Mandatory = $true)]
        [string]$DestVCenter,

        [Parameter(Mandatory = $false)]
        [bool]$VerboseDebug = $false
    )

    # Step 1: Move users to the target group
    foreach ($vm in $Batch) {
        Write-Host "Moving user $($vm.SamAccountName) to group $TargetGroup"
        Remove-ADGroupMember -Identity $InitialGroup -Members $vm.SamAccountName -Confirm:$False
        Add-ADGroupMember -Identity $TargetGroup -Members $vm.SamAccountName -Confirm:$False
    }

    # Step 2: Remove VMs from Horizon
    foreach ($vm in $Batch) {
        Write-Host "Removing $($vm.ComputerName)"
        Remove-HVMachine -MachineName $vm.ComputerName -DeleteFromDisk:$false -Confirm:$false -Verbose:$VerboseDebug -Debug:$VerboseDebug
    }
    Start-Sleep -Seconds 30  # Pause after removing all VMs

    # Step 3: Add VMs to Horizon Pool
    foreach ($vm in $Batch) {
        Write-Host "Adding $($vm.ComputerName) to $HorizonPoolName"
        Add-HVDesktop -poolname $HorizonPoolName -machines $vm.ComputerName -Vcenter $DestVCenter
    }
    Start-Sleep -Seconds 30  # Pause after adding all VMs

    # Step 4: Set machine users
    foreach ($vm in $Batch) {
        Write-Host "Setting machine $($vm.ComputerName) user to $($vm.SamAccountName)"
        Get-HVMachine -MachineName $vm.ComputerName | Set-HVMachine -User $vm.DistinguishedName
    }

    Write-Host "Horizon pool migration finished for the batch"
}
