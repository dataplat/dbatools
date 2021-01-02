function Copy-DbaAgentProxy {
    <#
    .SYNOPSIS
        Copy-DbaAgentProxy migrates proxy accounts from one SQL Server to another.

    .DESCRIPTION
        By default, all proxy accounts are copied. The -ProxyAccounts parameter is auto-populated for command-line completion and can be used to copy only specific proxy accounts.

        If the associated credential for the account does not exist on the destination, it will be skipped. If the proxy account already exists on the destination, it will be skipped unless -Force is used.

    .PARAMETER Source
        Source SQL Server. You must have sysadmin access and server version must be SQL Server version 2000 or higher.

    .PARAMETER SourceSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Destination
        Destination SQL Server. You must have sysadmin access and the server must be SQL Server 2000 or higher.

    .PARAMETER DestinationSqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER ProxyAccount
        Only migrate specific proxy accounts

    .PARAMETER ExcludeProxyAccount
        Migrate all proxy accounts except the ones explicitly excluded

    .PARAMETER WhatIf
        If this switch is enabled, no actions are performed but informational messages will be displayed that explain what would happen if the command were to run.

    .PARAMETER Confirm
        If this switch is enabled, you will be prompted for confirmation before executing any operations that change state.

    .PARAMETER Force
        If this switch is enabled, the Operator will be dropped and recreated on Destination.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Migration, Agent
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

        Requires: sysadmin access on SQL Servers

    .LINK
        https://dbatools.io/Copy-DbaAgentProxy

    .EXAMPLE
        PS C:\> Copy-DbaAgentProxy -Source sqlserver2014a -Destination sqlcluster

        Copies all proxy accounts from sqlserver2014a to sqlcluster using Windows credentials. If proxy accounts with the same name exist on sqlcluster, they will be skipped.

    .EXAMPLE
        PS C:\> Copy-DbaAgentProxy -Source sqlserver2014a -Destination sqlcluster -ProxyAccount PSProxy -SourceSqlCredential $cred -Force

        Copies only the PSProxy proxy account from sqlserver2014a to sqlcluster using SQL credentials for sqlserver2014a and Windows credentials for sqlcluster. If a proxy account with the same name exists on sqlcluster, it will be dropped and recreated because -Force was used.

    .EXAMPLE
        PS C:\> Copy-DbaAgentProxy -Source sqlserver2014a -Destination sqlcluster -WhatIf -Force

        Shows what would happen if the command were executed using force.

    #>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess, ConfirmImpact = "Medium")]
    param (
        [parameter(Mandatory)]
        [DbaInstanceParameter]$Source,
        [PSCredential]$SourceSqlCredential,
        [parameter(Mandatory)]
        [DbaInstanceParameter[]]$Destination,
        [PSCredential]$DestinationSqlCredential,
        [string[]]$ProxyAccount,
        [string[]]$ExcludeProxyAccount,
        [switch]$Force,
        [switch]$EnableException
    )
    begin {
        try {
            $sourceServer = Connect-SqlInstance -SqlInstance $Source -SqlCredential $SourceSqlCredential -MinimumVersion 9
        } catch {
            Stop-Function -Message "Error occurred while establishing connection to $Source" -Category ConnectionError -ErrorRecord $_ -Target $Source
            return
        }
        $serverProxyAccounts = $sourceServer.JobServer.ProxyAccounts
        if ($ProxyAccount) {
            $serverProxyAccounts = $serverProxyAccounts | Where-Object Name -in $ProxyAccount
        }
        if ($ExcludeProxyAccount) {
            $serverProxyAccounts = $serverProxyAccounts | Where-Object Name -notin $ExcludeProxyAccount
        }
        if ($Force) { $ConfirmPreference = 'none' }
    }
    process {
        if (Test-FunctionInterrupt) { return }
        foreach ($destinstance in $Destination) {
            try {
                $destServer = Connect-SqlInstance -SqlInstance $destinstance -SqlCredential $DestinationSqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $destinstance" -Category ConnectionError -ErrorRecord $_ -Target $destinstance -Continue
            }

            $destProxyAccounts = $destServer.JobServer.ProxyAccounts

            foreach ($account in $serverProxyAccounts) {
                $proxyName = $account.Name

                $copyAgentProxyAccountStatus = [pscustomobject]@{
                    SourceServer      = $sourceServer.Name
                    DestinationServer = $destServer.Name
                    Name              = $null
                    Type              = "Agent Proxy"
                    Status            = $null
                    Notes             = $null
                    DateTime          = [Sqlcollaborative.Dbatools.Utility.DbaDateTime](Get-Date)
                }

                $credentialName = $account.CredentialName
                $copyAgentProxyAccountStatus.Name = $proxyName
                $copyAgentProxyAccountStatus.Type = "Credential"

                # Proxy accounts rely on Credential accounts
                if (-not $CredentialName) {
                    $copyAgentProxyAccountStatus.Status = "Skipped"
                    $copyAgentProxyAccountStatus.Notes = "Skipping migration of $proxyName due to misconfigured (empty) credential name"
                    $copyAgentProxyAccountStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    Write-Message -Level Verbose -Message "Skipping migration of $proxyName due to misconfigured (empty) credential name"
                    continue
                }

                try {
                    $credentialtest = $destServer.Credentials[$CredentialName]
                } catch {
                    #here to avoid an empty catch
                    $null = 1
                }

                if ($null -eq $credentialtest) {
                    $copyAgentProxyAccountStatus.Status = "Skipped"
                    $copyAgentProxyAccountStatus.Notes = "Associated credential account, $CredentialName, does not exist on $destinstance"
                    $copyAgentProxyAccountStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    Write-Message -Level Verbose -Message "Associated credential account, $CredentialName, does not exist on $destinstance"
                    continue
                }

                if ($destProxyAccounts.Name -contains $proxyName) {
                    $copyAgentProxyAccountStatus.Name = $proxyName
                    $copyAgentProxyAccountStatus.Type = "ProxyAccount"

                    if ($force -eq $false) {
                        $copyAgentProxyAccountStatus.Status = "Skipped"
                        $copyAgentProxyAccountStatus.Notes = "Already exists on destination"
                        $copyAgentProxyAccountStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                        Write-Message -Level Verbose -Message "Server proxy account $proxyName exists at destination. Use -Force to drop and migrate."
                        Continue
                    } else {
                        if ($Pscmdlet.ShouldProcess($destinstance, "Dropping server proxy account $proxyName and recreating")) {
                            try {
                                Write-Message -Level Verbose -Message "Dropping server proxy account $proxyName"
                                $destServer.JobServer.ProxyAccounts[$proxyName].Drop()
                            } catch {
                                $copyAgentProxyAccountStatus.Status = "Failed"
                                $copyAgentProxyAccountStatus.Notes = "Could not drop"
                                $copyAgentProxyAccountStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                                Stop-Function -Message "Issue dropping proxy account" -Target $proxyName -ErrorRecord $_ -Continue
                            }
                        }
                    }
                }

                if ($Pscmdlet.ShouldProcess($destinstance, "Creating server proxy account $proxyName")) {
                    $copyAgentProxyAccountStatus.Name = $proxyName
                    $copyAgentProxyAccountStatus.Type = "ProxyAccount"

                    try {
                        Write-Message -Level Verbose -Message "Copying server proxy account $proxyName"
                        $sql = $account.Script() | Out-String
                        Write-Message -Level Debug -Message $sql
                        $destServer.Query($sql)

                        # Will fixing this misspelled status cause problems downstream?
                        $copyAgentProxyAccountStatus.Status = "Successful"
                        $copyAgentProxyAccountStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject
                    } catch {
                        $exceptionstring = $_.Exception.InnerException.ToString()
                        if ($exceptionstring -match 'subsystem') {
                            $copyAgentProxyAccountStatus.Status = "Skipping"
                            $copyAgentProxyAccountStatus.Notes = "Failure"
                            $copyAgentProxyAccountStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                            Write-Message -Level Verbose -Message "One or more subsystems do not exist on the destination server. Skipping that part."
                        } else {
                            $copyAgentProxyAccountStatus.Status = "Failed"
                            $copyAgentProxyAccountStatus | Select-DefaultView -Property DateTime, SourceServer, DestinationServer, Name, Type, Status, Notes -TypeName MigrationObject

                            Stop-Function -Message "Issue creating proxy account" -Target $proxyName -ErrorRecord $_
                        }
                    }
                }
            }
        }
    }
}