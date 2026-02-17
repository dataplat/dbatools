function Test-DbaInstanceName {
    <#
    .SYNOPSIS
        Validates SQL Server instance name consistency with the host OS and identifies rename requirements and potential blockers.

    .DESCRIPTION
        When a SQL Server's host OS is renamed, the SQL Server should be as well. This helps with Availability Groups and Kerberos.

        This command compares the SQL Server instance name (from @@servername) with the actual hostname and instance combination to determine if they match. When they don't match, a rename is typically required to prevent authentication issues and ensure proper cluster functionality.

        The function also performs critical safety checks by scanning for conditions that would prevent a safe rename, including active database mirroring, replication configurations (publishing, subscribing, or distribution), and remote login dependencies. Additionally, it identifies SQL Server Reporting Services installations that would require manual updates after a server rename.

        Use this before attempting any server rename operations to understand the scope of work involved and potential complications. The detailed output helps you plan the rename process and address blockers beforehand.

        https://www.mssqltips.com/sqlservertip/2525/steps-to-change-the-server-name-for-a-sql-server-machine/

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER ExcludeSsrs
        Skips checking for SQL Server Reporting Services installations that would require manual updates after a server rename.
        Use this switch when you know SSRS isn't installed or when you want to focus only on core SQL Server rename blockers.
        Without this switch, the function will warn about SSRS configurations that need attention during rename operations.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: SPN, Instance, Utility
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Test-DbaInstanceName

    .OUTPUTS
        PSCustomObject

        Returns one object per SQL Server instance analyzed, containing instance identification, current vs. expected server names, rename requirements, and any blockers preventing safe rename operations.

        Properties:
        - ComputerName: The name of the computer hosting the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance format)
        - ServerName: The current configured server name from @@servername
        - NewServerName: The expected server name based on hostname and instance name
        - RenameRequired: Boolean indicating whether a rename is needed (true when NewServerName differs from ServerName)
        - Updatable: Boolean or "N/A" - indicates if the instance can be safely renamed (false when blockers exist, true when safe, "N/A" when no rename needed)
        - Warnings: Warning message about SQL Server Reporting Services needing update if found, or "N/A" if not applicable
        - Blockers: Array of reasons preventing rename (database mirroring, replication, or remote logins), or "N/A" if no blockers exist

    .EXAMPLE
        PS C:\> Test-DbaInstanceName -SqlInstance sqlserver2014a

        Returns ServerInstanceName, SqlServerName, IsEqual and RenameRequired for sqlserver2014a.

    .EXAMPLE
        PS C:\> Test-DbaInstanceName -SqlInstance sqlserver2014a, sql2016

        Returns ServerInstanceName, SqlServerName, IsEqual and RenameRequired for sqlserver2014a and sql2016.

    .EXAMPLE
        PS C:\> Test-DbaInstanceName -SqlInstance sqlserver2014a, sql2016 -ExcludeSsrs

        Returns ServerInstanceName, SqlServerName, IsEqual and RenameRequired for sqlserver2014a and sql2016, but skips validating if SSRS is installed on both instances.

    .EXAMPLE
        PS C:\> Test-DbaInstanceName -SqlInstance sqlserver2014a, sql2016 | Select-Object *

        Returns ServerInstanceName, SqlServerName, IsEqual and RenameRequired for sqlserver2014a and sql2016.
        If a Rename is required, it will also show Updatable, and Reasons if the server name is not updatable.

    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch]$ExcludeSsrs,
        [switch]$EnableException
    )
    process {

        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($server.IsClustered) {
                Write-Message -Level Warning -Message "$instance is a cluster. Renaming clusters is not supported by Microsoft."
            }

            $configuredServerName = $server.Query("SELECT @@servername AS ServerName").ServerName
            Write-Message -Level Verbose -Message "configuredServerName from @@servername is $configuredServerName"

            $instanceName = $server.InstanceName
            Write-Message -Level Verbose -Message "server.InstanceName is $instanceName"
            $netName = $server.NetName
            Write-Message -Level Verbose -Message "server.NetName is $netName"

            if ($instanceName.Length -eq 0) {
                $newServerName = $netName
                $instanceName = "MSSQLSERVER"
            } else {
                $newServerName = "$netName\$instanceName"
            }
            Write-Message -Level Verbose -Message "newServerName is $newServerName"

            # output some other properties that migth help to get the new servername
            Write-Message -Level Debug -Message "server.ComputerName is $($server.ComputerName)"
            Write-Message -Level Debug -Message "server.ComputerNamePhysicalNetBIOS is $($server.ComputerNamePhysicalNetBIOS)"
            Write-Message -Level Debug -Message "server.DomainInstanceName is $($server.DomainInstanceName)"
            Write-Message -Level Debug -Message "server.Name is $($server.Name)"
            Write-Message -Level Debug -Message "server.NetName is $($server.NetName)"
            Write-Message -Level Debug -Message "server.ServiceName is $($server.ServiceName)"

            $serverInfo = [PSCustomObject]@{
                ComputerName   = $server.ComputerName
                InstanceName   = $server.ServiceName
                SqlInstance    = $server.DomainInstanceName
                ServerName     = $configuredServerName
                NewServerName  = $newServerName
                RenameRequired = $newServerName -ne $configuredServerName
                Updatable      = "N/A"
                Warnings       = $null
                Blockers       = $null
            }

            $reasons = @()
            $ssrsService = "SQL Server Reporting Services ($instanceName)"

            Write-Message -Level Verbose -Message "Checking for $serverName on $netBiosName"
            $rs = $null
            if ($SkipSsrs -eq $false -or $NoWarning -eq $false) {
                try {
                    $rs = Get-DbaService -ComputerName $instance.ComputerName -InstanceName $server.ServiceName -Type SSRS -EnableException -WarningAction Stop
                } catch {
                    Write-Message -Level Warning -Message "Unable to pull information on $ssrsService." -ErrorRecord $_ -Target $instance
                }
            }

            if ($null -ne $rs -or $rs.Count -gt 0) {
                if ($rs.State -eq 'Running') {
                    $rstext = "$ssrsService must be stopped and updated."
                } else {
                    $rstext = "$ssrsService exists. When it is started again, it must be updated."
                }
                $serverInfo.Warnings = $rstext
            } else {
                $serverInfo.Warnings = "N/A"
            }

            # check for mirroring
            $mirroredDb = $server.Databases | Where-Object { $_.IsMirroringEnabled -eq $true }

            Write-Message -Level Debug -Message "Found the following mirrored dbs: $($mirroredDb.Name)"

            if ($mirroredDb.Length -gt 0) {
                $dbs = $mirroredDb.Name -join ", "
                $reasons += "Databases are being mirrored: $dbs"
            }

            # check for replication
            $sql = "SELECT name FROM sys.databases WHERE is_published = 1 OR is_subscribed = 1 OR is_distributor = 1"
            Write-Message -Level Debug -Message "SQL Statement: $sql"
            $replicatedDb = $server.Query($sql)

            if ($replicatedDb.Count -gt 0) {
                $dbs = $replicatedDb.Name -join ", "
                $reasons += "Database(s) are involved in replication: $dbs"
            }

            # check for even more replication
            $sql = "SELECT srl.remote_name AS RemoteLoginName FROM sys.remote_logins srl JOIN sys.sysservers sss ON srl.server_id = sss.srvid"
            Write-Message -Level Debug -Message "SQL Statement: $sql"
            $results = $server.Query($sql)

            if ($results.RemoteLoginName.Count -gt 0) {
                $remoteLogins = $results.RemoteLoginName -join ", "
                $reasons += "Remote logins still exist: $remoteLogins"
            }

            if ($reasons.Length -gt 0) {
                $serverInfo.Updatable = $false
                $serverInfo.Blockers = $reasons
            } else {
                $serverInfo.Updatable = $true
                $serverInfo.Blockers = "N/A"
            }

            $serverInfo
        }
    }
}