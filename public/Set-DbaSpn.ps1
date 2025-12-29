function Set-DbaSpn {
    <#
    .SYNOPSIS
        Sets an SPN for a given service account in active directory (and also enables delegation to the same SPN by default)

    .DESCRIPTION
        This function will connect to Active Directory and search for an account. If the account is found, it will attempt to add an SPN. Once the SPN is added, the function will also set delegation to that service, unless -NoDelegation is specified. In order to run this function, the credential you provide must have write access to Active Directory.

        Note: This function supports -WhatIf

    .PARAMETER SPN
        Specifies the Service Principal Name to register in Active Directory for SQL Server Kerberos authentication.
        Must follow the format 'MSSQLSvc/hostname:port' or 'MSSQLSvc/FQDN:port' for named instances.
        Use this to enable Kerberos authentication and eliminate double-hop authentication issues.

    .PARAMETER ServiceAccount
        Specifies the Active Directory account that runs the SQL Server service and will own the SPN.
        Can be a domain user account (domain\username) or computer account (computername$) depending on your SQL Server service configuration.
        This account must exist in Active Directory and you must have permissions to modify its properties.

    .PARAMETER Credential
        The credential you want to use to connect to Active Directory to make the changes

    .PARAMETER NoDelegation
        Prevents automatic configuration of Kerberos constrained delegation for the specified SPN.
        Use this when you want to manually configure delegation later or when delegation is not required for your environment.
        By default, the function enables constrained delegation to allow the service account to authenticate to other services.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .PARAMETER Confirm
        Turns confirmations before changes on or off

    .PARAMETER WhatIf
        Shows what would happen if the command was executed

    .NOTES
        Tags: SPN
        Author: Drew Furgiuele (@pittfurg), port1433.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Set-DbaSpn

    .OUTPUTS
        PSCustomObject

        Returns one or two objects per service account processed, depending on delegation configuration:

        SPN Registration Result Object (always returned):
        - Name (string) - The Service Principal Name that was added
        - ServiceAccount (string) - The Active Directory account that owns the SPN
        - Property (string) - Always "servicePrincipalName" indicating the AD property that was modified
        - IsSet (boolean) - True if the SPN was successfully added, False if the operation failed
        - Notes (string) - Status message: "Successfully added SPN" or "Failed to add SPN"

        Delegation Configuration Result Object (conditionally returned):
        - Name (string) - The Service Principal Name for which delegation was configured
        - ServiceAccount (string) - The Active Directory account for which delegation was configured
        - Property (string) - Always "msDS-AllowedToDelegateTo" indicating the AD property that was modified
        - IsSet (boolean) - True if constrained delegation was successfully enabled, False if the operation failed
        - Notes (string) - Status message: "Successfully added constrained delegation" or "Failed to add constrained delegation"

        The delegation object is only returned when:
        - The SPN was successfully added (IsSet = $true for the first object)
        - AND the -NoDelegation parameter was NOT specified
        - AND the ShouldProcess check passed (when -WhatIf is not used)

        When -NoDelegation is specified, only the SPN registration object is returned.

    .EXAMPLE
        PS C:\> Set-DbaSpn -SPN MSSQLSvc/SQLSERVERA.domain.something -ServiceAccount domain\account
        PS C:\> Set-DbaSpn -SPN MSSQLSvc/SQLSERVERA.domain.something -ServiceAccount domain\account -EnableException

        Connects to Active Directory and adds a provided SPN to the given account.
        Connects to Active Directory and adds a provided SPN to the given account, suppressing all error messages and throw exceptions that can be caught instead

    .EXAMPLE
        PS C:\> Set-DbaSpn -SPN MSSQLSvc/SQLSERVERA.domain.something -ServiceAccount domain\account -Credential ad\sqldba

        Connects to Active Directory and adds a provided SPN to the given account. Uses alternative account to connect to AD.

    .EXAMPLE
        PS C:\> Set-DbaSpn -SPN MSSQLSvc/SQLSERVERA.domain.something -ServiceAccount domain\account -NoDelegation

        Connects to Active Directory and adds a provided SPN to the given account, without the delegation.

    .EXAMPLE
        PS C:\> Test-DbaSpn -ComputerName sql2016 | Where-Object { $_.isSet -eq $false } | Set-DbaSpn

        Sets all missing SPNs for sql2016

    .EXAMPLE
        PS C:\> Test-DbaSpn -ComputerName sql2016 | Where-Object { $_.isSet -eq $false } | Set-DbaSpn -WhatIf

        Displays what would happen trying to set all missing SPNs for sql2016

    #>
    [cmdletbinding(SupportsShouldProcess, DefaultParameterSetName = "Default")]
    param (
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias("RequiredSPN")]
        [string]$SPN,
        [Parameter(Mandatory, ValueFromPipelineByPropertyName)]
        [Alias("InstanceServiceAccount", "AccountName")]
        [string]$ServiceAccount,
        [Parameter(ValueFromPipelineByPropertyName)]
        [PSCredential]$Credential,
        [switch]$NoDelegation,
        [switch]$EnableException
    )

    process {
        #did we find the server account?
        Write-Message -Message "Looking for account $ServiceAccount..." -Level Verbose
        $searchfor = 'User'
        if ($ServiceAccount.EndsWith('$')) {
            $searchfor = 'Computer'
        }
        try {
            $Result = Get-DbaADObject -ADObject $ServiceAccount -Type $searchfor -Credential $Credential -EnableException
        } catch {
            Stop-Function -Message "AD lookup failure. This may be because the domain cannot be resolved for the SQL Server service account ($ServiceAccount). $($_.Exception.Message)" -EnableException $EnableException -InnerErrorRecord $_ -Target $ServiceAccount
        }
        if ($Result.Count -gt 0) {
            try {
                $adentry = $Result.GetUnderlyingObject()
            } catch {
                Stop-Function -Message "The SQL Service account ($ServiceAccount) has been found, but you don't have enough permission to inspect its properties $($_.Exception.Message)" -EnableException $EnableException -InnerErrorRecord $_ -Target $ServiceAccount
            }
        } else {
            Stop-Function -Message "The SQL Service account ($ServiceAccount) has not been found" -EnableException $EnableException -Target $ServiceAccount
        }
        # Cool! Add an SPN
        $delegate = $true
        if ($PSCmdlet.ShouldProcess("$spn", "Adding SPN to service account")) {
            try {
                $null = $adentry.Properties['serviceprincipalname'].Add($spn)
                $status = "Successfully added SPN"
                $adentry.CommitChanges()
                Write-Message -Message "Added SPN $spn to $ServiceAccount" -Level Verbose
                $set = $true
            } catch {
                Write-Message -Message "Could not add SPN. $($_.Exception.Message)" -Level Warning -EnableException $EnableException.ToBool() -ErrorRecord $_ -Target $ServiceAccount
                $set = $false
                $status = "Failed to add SPN"
                $delegate = $false
            }

            [PSCustomObject]@{
                Name           = $spn
                ServiceAccount = $ServiceAccount
                Property       = "servicePrincipalName"
                IsSet          = $set
                Notes          = $status
            }
        }

        #if we have the SPN set, we can add the delegation
        if ($delegate) {
            # but only if $NoDelegation is not passed
            if (!$NoDelegation) {
                if ($PSCmdlet.ShouldProcess("$spn", "Adding constrained delegation to service account for SPN")) {
                    try {
                        $null = $adentry.Properties['msDS-AllowedToDelegateTo'].Add($spn)
                        $adentry.CommitChanges()
                        Write-Message -Message "Added kerberos delegation to $spn for $ServiceAccount" -Level Verbose
                        $set = $true
                        $status = "Successfully added constrained delegation"
                    } catch {
                        Write-Message -Message "Could not add delegation. $($_.Exception.Message)" -Level Warning -EnableException $EnableException.ToBool() -ErrorRecord $_ -Target $ServiceAccount
                        $set = $false
                        $status = "Failed to add constrained delegation"
                    }

                    [PSCustomObject]@{
                        Name           = $spn
                        ServiceAccount = $ServiceAccount
                        Property       = "msDS-AllowedToDelegateTo"
                        IsSet          = $set
                        Notes          = $status
                    }
                }
            } else {
                Write-Message -Message "Skipping delegation as instructed" -Level Verbose
            }
        }
    }
}