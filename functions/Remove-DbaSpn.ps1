function Remove-DbaSpn {
    <#
    .SYNOPSIS
        Removes an SPN for a given service account in active directory and also removes delegation to the same SPN, if found

    .DESCRIPTION
        This function will connect to Active Directory and search for an account. If the account is found, it will attempt to remove the specified SPN. Once the SPN is removed, the function will also remove delegation to that service.

        In order to run this function, the credential you provide must have write access to Active Directory.

    .PARAMETER SPN
        The SPN you want to remove

    .PARAMETER ServiceAccount
        The account you want the SPN remove from

    .PARAMETER Credential
        The credential you want to use to connect to Active Directory to make the changes

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
        Author: Drew Furgiuele (@pittfurg), http://www.port1433.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Remove-DbaSpn

    .EXAMPLE
        PS C:\> Remove-DbaSpn -SPN MSSQLSvc\SQLSERVERA.domain.something -ServiceAccount domain\account

        Connects to Active Directory and removes a provided SPN from the given account (and also the relative delegation)

    .EXAMPLE
        PS C:\> Remove-DbaSpn -SPN MSSQLSvc\SQLSERVERA.domain.something -ServiceAccount domain\account -EnableException

        Connects to Active Directory and removes a provided SPN from the given account, suppressing all error messages and throw exceptions that can be caught instead

    .EXAMPLE
        PS C:\> Remove-DbaSpn -SPN MSSQLSvc\SQLSERVERA.domain.something -ServiceAccount domain\account -Credential ad\sqldba

        Connects to Active Directory and removes a provided SPN to the given account. Uses alternative account to connect to AD.

    .EXAMPLE
        PS C:\> Test-DbaSpn -ComputerName sql2005 | Where-Object { $_.isSet -eq $true } | Remove-DbaSpn -WhatIf

        Shows what would happen trying to remove all set SPNs for sql2005 and the relative delegations

    .EXAMPLE
        PS C:\> Test-DbaSpn -ComputerName sql2005 | Where-Object { $_.isSet -eq $true } | Remove-DbaSpn

        Removes all set SPNs for sql2005 and the relative delegations

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
        [switch]$EnableException
    )

    process {
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

        # Cool! Remove an SPN
        $delegate = $true
        $spnadobject = $adentry.Properties['servicePrincipalName']

        if ($spnadobject -notcontains $spn) {
            Write-Message -Level Warning -Message "SPN $SPN not found"
            $status = "SPN not found"
            $set = $false
        }

        if ($PSCmdlet.ShouldProcess("$spn", "Removing SPN for service account")) {
            try {
                if ($spnadobject -contains $spn) {
                    $null = $spnadobject.Remove($spn)
                    $adentry.CommitChanges()
                    Write-Message -Message "Remove SPN $spn for $ServiceAccount" -Level Verbose
                    $set = $false
                    $status = "Successfully removed SPN"
                }
            } catch {
                Write-Message -Message "Could not remove SPN. $($_.Exception.Message)" -Level Warning -EnableException $EnableException.ToBool() -ErrorRecord $_ -Target $ServiceAccountWrite
                $set = $true
                $status = "Failed to remove SPN"
                $delegate = $false
            }

            [pscustomobject]@{
                Name           = $spn
                ServiceAccount = $ServiceAccount
                Property       = "servicePrincipalName"
                IsSet          = $set
                Notes          = $status
            }
        }
        # if we removed the SPN, we should clean up also the delegation
        if ($PSCmdlet.ShouldProcess("$spn", "Removing delegation for service account for SPN")) {
            # if we didn't remove the SPN we shouldn't do anything
            if ($delegate) {
                # even if we removed the SPN, delegation could have been not set at all. We should not raise an error
                if ($adentry.Properties['msDS-AllowedToDelegateTo'] -notcontains $spn) {
                    [pscustomobject]@{
                        Name           = $spn
                        ServiceAccount = $ServiceAccount
                        Property       = "msDS-AllowedToDelegateTo"
                        IsSet          = $false
                        Notes          = "Delegation not found"
                    }
                } else {
                    # we indeed need the cleanup
                    try {
                        $null = $adentry.Properties['msDS-AllowedToDelegateTo'].Remove($spn)
                        $adentry.CommitChanges()
                        Write-Message -Message "Removed kerberos delegation $spn for $ServiceAccount" -Level Verbose
                        $set = $false
                        $status = "Successfully removed delegation"
                    } catch {
                        Write-Message -Message "Could not remove delegation. $($_.Exception.Message)" -Level Warning -EnableException $EnableException.ToBool() -ErrorRecord $_ -Target $ServiceAccount
                        $set = $true
                        $status = "Failed to remove delegation"
                    }

                    [pscustomobject]@{
                        Name           = $spn
                        ServiceAccount = $ServiceAccount
                        Property       = "msDS-AllowedToDelegateTo"
                        IsSet          = $set
                        Notes          = $status
                    }
                }
            }

        }
    }
}