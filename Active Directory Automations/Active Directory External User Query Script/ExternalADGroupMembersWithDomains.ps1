<#
.SYNOPSIS
    Queries multiple Active Directory groups for user details across internal and external domains.

.DESCRIPTION
    This PowerShell script is designed for administrators managing multi-domain environments. It queries multiple Active Directory groups, including those in external domains with bidirectional trust relationships. The script retrieves users' display names, domain affiliations, and group memberships, outputting this information to both the console and a CSV file for easy review and record-keeping. Optimal performance is achieved when the script is run on a domain controller.

.PARAMETER GroupNames
    An array of Active Directory group names to query. Example: @("group1", "group2", "groupN")

.PARAMETER OutputFile
    The file path where the output CSV file will be saved. Example: "C:\OutputFile.csv"

.EXAMPLE
    .\ExternalADGroupMembersWithDomains.ps1
    Executes the script with predefined group names and an output file path.

.NOTES
    File Name  : ExternalADGroupMembersWithDomains.ps1
    Author     : https://github.com/rergards
    Version    : 1.01
    Last Update: 2023-12-04
    Prerequisite: PowerShell 5.0 or higher, Active Directory module.

#>

# Cleanup of all variables in current session
Get-Variable | ForEach-Object { Remove-Variable -Name $_.Name -ErrorAction SilentlyContinue }

# Specify the group names and output file path
$GroupNames = @("group1", "group2", "groupN")
$OutputFile = "C:\OutputFile.csv"

# Initialize the result array
$Result = @()

# Iterate through each group name
foreach ($GroupName in $GroupNames) {
    # Get the AD group object
    $Group = Get-ADGroup -Filter {Name -eq $GroupName}

    # Set up a DirectorySearcher to find the group in LDAP
    $Searcher = New-Object System.DirectoryServices.DirectorySearcher
    $Searcher.Filter = "(&(objectClass=group)(name=$($GroupName)))"
    $Searcher.SearchScope = "Subtree"

    # Set the search root to the default naming context
    $RootDSE = [System.DirectoryServices.DirectoryEntry]"LDAP://RootDSE"
    $Searcher.SearchRoot = [System.DirectoryServices.DirectoryEntry]"LDAP://$($RootDSE.defaultNamingContext)"

    # Perform the search
    $SearchResult = $Searcher.FindOne()

    # If the group is found, process the members
    if ($SearchResult) {
        # Get the member distinguished names
        $Members = $SearchResult.Properties["member"]

        # Iterate through each member distinguished name
        foreach ($MemberDN in $Members) {
            try {
                # Get the member object
                $Member = [ADSI]"LDAP://$MemberDN"

                # If the member is a foreign security principal, translate the SID to an NTAccount
                if ($Member.ObjectClass -eq 'foreignSecurityPrincipal') {
                    $FSP = New-Object System.Security.Principal.SecurityIdentifier($Member.objectSid[0], 0)
                    $NTAccount = $FSP.Translate([System.Security.Principal.NTAccount])
                    $UserSamAccountName = $NTAccount.Value.Split('\')[-1]
                    $UserDomain = $NTAccount.Value.Split('\')[0]

                    # Get the user object from the external domain
                    $User = Get-ADUser -Identity $UserSamAccountName -Properties DisplayName, DistinguishedName -Server "$UserDomain"

                } else {
                    # Get the user object from the current domain
                    $User = Get-ADUser -Identity $MemberDN -Properties DisplayName, DistinguishedName
                }

                # Extract the domain from the user's distinguished name
                $Domain = ($User.DistinguishedName -split ',')[-2] -replace 'DC=', ''

                # Add the user information to the result array
                $Result += New-Object PSObject -Property @{
                    DisplayName = $User.DisplayName
                    Domain      = $Domain
                    Group       = $GroupName
                }
            } catch {
                # Log the error and add the error information to the result array
                Write-Host "Error processing user: $MemberDN"
                Write-Host "Exception: $_.Exception.Message"

                $ErrorUser = $NTAccount.Value
                $Result += New-Object PSObject -Property @{
                    DisplayName = "Error: $ErrorUser"
                    Domain      = "Error"
                    Group       = $GroupName
                }
            }
        }
    } else {
        # Log that the group was not found
        Write-Host "Group not found: $GroupName"
    }
}

# Print the user count and results
$UserCount = $Result.Count
Write-Host "User count: $UserCount"
$Result | ForEach-Object { Write-Host "DisplayName: $($_.DisplayName), Domain: $($_.Domain), Group: $($_.Group)" }

# Export the results to a CSV file
$Result | Export-Csv -Path $OutputFile -NoTypeInformation -Encoding UTF8

# Clear variables
Remove-Variable Group, Members, UserCount, Result, Searcher, SearchResult