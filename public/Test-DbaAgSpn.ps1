function Test-DbaAgSpn {
    <#
    .SYNOPSIS
        Validates Service Principal Name registration for Availability Group listeners in Active Directory

    .DESCRIPTION
        Checks whether the required SPNs are properly registered in Active Directory for each Availability Group listener's service account. This function queries AD to verify that both the MSSQLSvc/listener.domain.com and MSSQLSvc/listener.domain.com:port SPNs exist, which are essential for Kerberos authentication to work correctly with AG listeners.

        Use this to troubleshoot client connectivity issues, validate SPN configuration before deployments, or audit security compliance. Missing SPNs will cause authentication failures when clients attempt to connect using integrated Windows authentication through the listener.

        https://learn.microsoft.com/en-us/sql/database-engine/availability-groups/windows/listeners-client-connectivity-application-failover?view=sql-server-ver16#SPNs was used as a guide

    .PARAMETER SqlInstance
        The target SQL Server instance or instances. Server version must be SQL Server version 2012 or higher.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Credential
        Alternative credential for connecting to Active Directory.

    .PARAMETER AvailabilityGroup
        The availability group to test. If not specified, all availability groups will be tested.

    .PARAMETER Listener
        The availability group listener to test. If not specified, all listeners will be tested.

    .PARAMETER InputObject
        Enables piped input from Get-DbaAvailabilityGroup.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: AG, HA
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2023 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Test-DbaAgSpn

    .EXAMPLE
        PS C:\> Get-DbaAvailabilityGroup -SqlInstance sql01 -AvailabilityGroup SharePoint | Test-DbaAgSpn

        Tests the SPNs for the SharePoint availability group listeners on sql01

    .EXAMPLE
        PS C:\> Test-DbaAgSpn -SqlInstance sql01 -AvailabilityGroup SharePoint -Listener spag01

        Tests the spag01 SPN for the SharePoint availability group listener on sql01

    .EXAMPLE
        PS C:\> Test-DbaAgSpn -SqlInstance sql01 | Set-DbaSpn

        Tests the SPNs for all availability group listeners on sql01 and sets them if they are not set

    #>
    [CmdletBinding()]
    param (
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [PSCredential]$Credential,
        [string[]]$AvailabilityGroup,
        [string[]]$Listener,
        [parameter(ValueFromPipeline)]
        [Microsoft.SqlServer.Management.Smo.AvailabilityGroup[]]$InputObject,
        [switch]$EnableException
    )
    begin {
        # spare the cmdlet to search for the same account over and over
        $resultCache = @{ }
        $spns = @()
    }
    process {
        if (Test-Bound -Not SqlInstance, InputObject) {
            Stop-Function -Message "You must supply either -SqlInstance or an Input Object"
            return
        }

        if ($SqlInstance) {
            $InputObject += Get-DbaAvailabilityGroup -SqlInstance $SqlInstance -AvailabilityGroup $AvailabilityGroup -SqlCredential $SqlCredential
        }

        foreach ($ag in $InputObject) {
            Write-Message -Level Verbose -Message "Processing $($ag.Name) on $($ag.Parent.Name)"
            if (-not $Listener) {
                $listeners = $ag | Get-DbaAgListener
            } else {
                Write-Warning poot
                $listeners = $ag | Get-DbaAgListener -Listener $Listener
            }

            # ([System.Net.Dns]::GetHostEntry($hostEntry)).HostName
            foreach ($aglistener in $listeners) {
                Write-Message -Level Verbose -Message "Processing $($aglistener.Name) on $($aglistener.Parent.Name)"
                $server = $aglistener.Parent.Parent
                $platform = $server.Platform -split " " | Select-Object -Last 1
                $version = $server.VersionString, $server.DatabaseEngineEdition, "Edition", $platform -join " "
                $port = $aglistener.PortNumber

                $fqdn = $server.Information.FullyQualifiedNetName
                $dnsname = ($fqdn -split "\." | Select-Object -Skip 1) -join "."
                $hostEntry = $aglistener.Name, $dnsname -join "."

                if ($aglistener.InstanceName -eq "MSSQLSERVER") {
                    $required = "MSSQLSvc/$hostEntry"
                } else {
                    $required = "MSSQLSvc/" + $hostEntry + ":" + $aglistener.InstanceName
                }

                $spns += [PSCustomObject] @{
                    ComputerName           = $server.Information.FullyQualifiedNetName
                    SqlInstance            = $aglistener.SqlInstance
                    InstanceName           = $aglistener.InstanceName
                    SqlProduct             = $version
                    InstanceServiceAccount = $server.ServiceAccount
                    RequiredSPN            = $required
                    IsSet                  = $false
                    Cluster                = $server.IsClustered
                    TcpEnabled             = $true
                    Port                   = $port
                    DynamicPort            = $false
                    Warning                = "None"
                    Error                  = "None"
                    Credential             = $Credential
                }

                $spns += [PSCustomObject] @{
                    ComputerName           = $server.Information.FullyQualifiedNetName
                    SqlInstance            = $aglistener.SqlInstance
                    InstanceName           = $aglistener.InstanceName
                    SqlProduct             = $version
                    InstanceServiceAccount = $server.ServiceAccount
                    RequiredSPN            = "MSSQLSvc/$hostEntry" + ":" + $port
                    IsSet                  = $false
                    Cluster                = $server.IsClustered
                    TcpEnabled             = $true
                    Port                   = $port
                    DynamicPort            = $false
                    Warning                = "None"
                    Error                  = "None"
                    Credential             = $Credential
                }
            }
        }

        foreach ($spn in $spns) {
            Write-Message -Level Verbose -Message "Processing SPN on $($spn.SqlInstance)"
            $searchfor = 'User'
            if ($spn.InstanceServiceAccount -eq 'LocalSystem' -or $spn.InstanceServiceAccount -like 'NT SERVICE\*') {
                Write-Message -Level Verbose -Message "Virtual account detected, changing target registration to computername"
                $spn.InstanceServiceAccount = "$($resolved.Domain)\$($resolved.ComputerName)$"
                $searchfor = 'Computer'
            } elseif ($spn.InstanceServiceAccount -like '*\*$') {
                Write-Message -Level Verbose -Message "Managed Service Account detected"
                $searchfor = 'Computer'
            }

            $serviceAccount = $spn.InstanceServiceAccount
            # spare the cmdlet to search for the same account over and over
            if ($spn.InstanceServiceAccount -notin $resultCache.Keys) {
                Write-Message -Message "Searching for $serviceAccount" -Level Verbose
                try {
                    $result = Get-DbaADObject -ADObject $serviceAccount -Type $searchfor -Credential $Credential -EnableException
                    $resultCache[$spn.InstanceServiceAccount] = $result
                } catch {
                    if (![System.String]::IsNullOrEmpty($spn.InstanceServiceAccount)) {
                        Write-Message -Message "AD lookup failure. This may be because the domain cannot be resolved for the SQL Server service account ($serviceAccount)." -Level Warning
                    }
                }
            } else {
                $result = $resultCache[$spn.InstanceServiceAccount]
            }
            if ($result.Count -gt 0) {
                try {
                    $results = $result.GetUnderlyingObject()
                    if ($results.Properties.servicePrincipalName -contains $spn.RequiredSPN) {
                        $spn.IsSet = $true
                    }
                } catch {
                    Write-Message -Message "The SQL Service account ($serviceAccount) has been found, but you don't have enough permission to inspect its SPNs" -Level Warning
                    continue
                }
            } else {
                Write-Message -Level Warning -Message "SQL Service account not found. Results may not be accurate."
                $spn
                continue
            }
            if (!$spn.IsSet -and $spn.TcpEnabled) {
                $spn.Error = "SPN missing"
            }

            $spn | Select-DefaultView -ExcludeProperty Credential, DomainName
        }
    }
}