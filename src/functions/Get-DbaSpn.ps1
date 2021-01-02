function Get-DbaSpn {
    <#
    .SYNOPSIS
        Returns a list of set service principal names for a given computer/AD account

    .DESCRIPTION
        Get a list of set SPNs. SPNs are set at the AD account level. You can either retrieve set SPNs for a computer, or any SPNs set for
        a given active directory account. You can query one, or both. You'll get a list of every SPN found for either search term.

    .PARAMETER ComputerName
        The servers you want to return set SPNs for. This is defaulted automatically to localhost.

    .PARAMETER AccountName
        The accounts you want to retrieve set SPNs for.

    .PARAMETER Credential
        User credential to connect to the remote servers or active directory.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: SPN
        Author: Drew Furgiuele (@pittfurg), http://www.port1433.com

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaSpn

    .EXAMPLE
        PS C:\> Get-DbaSpn -ComputerName SQLSERVERA -Credential ad\sqldba

        Returns a custom object with SearchTerm (ServerName) and the SPNs that were found

    .EXAMPLE
        PS C:\> Get-DbaSpn -AccountName domain\account -Credential ad\sqldba

        Returns a custom object with SearchTerm (domain account) and the SPNs that were found

    .EXAMPLE
        PS C:\> Get-DbaSpn -ComputerName SQLSERVERA,SQLSERVERB -Credential ad\sqldba

        Returns a custom object with SearchTerm (ServerName) and the SPNs that were found for multiple computers

    #>
    [cmdletbinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseApprovedVerbs", "", Justification = "Internal functions are ignored")]
    param (
        [Parameter(ValueFromPipeline)]
        [string[]]$ComputerName,
        [string[]]$AccountName,
        [PSCredential]$Credential,
        [switch]$EnableException
    )
    begin {
        Function Process-Account ($AccountName) {

            ForEach ($account in $AccountName) {
                Write-Message -Message "Looking for account $account..." -Level Verbose
                $searchfor = 'User'
                if ($account.EndsWith('$')) {
                    $searchfor = 'Computer'
                }
                try {
                    $Result = Get-DbaADObject -ADObject $account -Type $searchfor -Credential $Credential -EnableException
                } catch {
                    Write-Message -Message "AD lookup failure. This may be because the domain cannot be resolved for the SQL Server service account ($Account)." -Level Warning
                    continue
                }
                if ($Result.Count -gt 0) {
                    try {
                        $results = $Result.GetUnderlyingObject()
                        $spns = $results.Properties.servicePrincipalName
                    } catch {
                        Write-Message -Message "The SQL Service account ($Account) has been found, but you don't have enough permission to inspect its SPNs" -Level Warning
                        continue
                    }
                } else {
                    Write-Message -Message "The SQL Service account ($Account) has not been found" -Level Warning
                    continue
                }

                foreach ($spn in $spns) {
                    if ($spn -match "\:") {
                        try {
                            $port = [int]($spn -Split "\:")[1]
                        } catch {
                            $port = $null
                        }
                        #Variable marked as unused by PSScriptAnalyzer
                        # if ($spn -match "\/") {
                        #     $serviceclass = ($spn -Split "\/")[0]
                        # }
                    }
                    [pscustomobject] @{
                        Input        = $Account
                        AccountName  = $Account
                        ServiceClass = "MSSQLSvc" # $serviceclass
                        Port         = $port
                        SPN          = $spn
                    }
                }
            }
        }
        if ($ComputerName.Count -eq 0 -and $AccountName.Count -eq 0) {
            $ComputerName = @($env:COMPUTERNAME)
        }
    }

    process {

        foreach ($computer in $ComputerName) {
            if ($computer) {
                if ($computer.EndsWith('$')) {
                    Write-Message -Message "$computer is an account name. Processing as account." -Level Verbose
                    Process-Account -AccountName $computer
                    continue
                }
            }

            Write-Message -Message "Getting SQL Server SPN for $computer" -Level Verbose
            $spns = Test-DbaSpn -ComputerName $computer -Credential $Credential

            $sqlspns = 0
            $spncount = $spns.count
            Write-Message -Message "Calculated $spncount SQL SPN entries that should exist for $computer" -Level Verbose
            foreach ($spn in $spns | Where-Object { $_.IsSet -eq $true }) {
                $sqlspns++

                if ($accountName) {
                    if ($accountName -eq $spn.InstanceServiceAccount) {
                        [pscustomobject] @{
                            Input        = $computer
                            AccountName  = $spn.InstanceServiceAccount
                            ServiceClass = "MSSQLSvc"
                            Port         = $spn.Port
                            SPN          = $spn.RequiredSPN
                        }
                    }
                } else {
                    [pscustomobject] @{
                        Input        = $computer
                        AccountName  = $spn.InstanceServiceAccount
                        ServiceClass = "MSSQLSvc"
                        Port         = $spn.Port
                        SPN          = $spn.RequiredSPN
                    }
                }
            }
            Write-Message -Message "Found $sqlspns set SQL SPN entries for $computer" -Level Verbose
        }

        if ($AccountName) {
            foreach ($account in $AccountName) {
                Process-Account -AccountName $account
            }
        }
    }
}