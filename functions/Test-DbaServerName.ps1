function Test-DbaServerName {
    <#
        .SYNOPSIS
            Tests to see if it's possible to easily rename the server at the SQL Server instance level, or if it even needs to be changed.

        .DESCRIPTION
            When a SQL Server's host OS is renamed, the SQL Server should be as well. This helps with Availability Groups and Kerberos.

            This command helps determine if your OS and SQL Server names match, and whether a rename is required.

            It then checks conditions that would prevent a rename, such as database mirroring and replication.

            https://www.mssqltips.com/sqlservertip/2525/steps-to-change-the-server-name-for-a-sql-server-machine/

        .PARAMETER SqlInstance
            The SQL Server that you're connecting to.

        .PARAMETER SqlCredential
            Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

            $scred = Get-Credential, then pass $scred object to the -Credential parameter.

            Windows Authentication will be used if Credential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

            To connect as a different Windows user, run PowerShell as that user.

        .PARAMETER Detailed
            Output all properties, will be deprecated in 1.0.0 release.

        .PARAMETER ExcludeSsrs
            If this switch is enabled, checking for SQL Server Reporting Services will be skipped.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: SPN, ServerName

            dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
            Copyright (C) 2016 Chrissy LeMaire
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .LINK
            https://dbatools.io/Test-DbaServerName

        .EXAMPLE
            Test-DbaServerName -SqlInstance sqlserver2014a

            Returns ServerInstanceName, SqlServerName, IsEqual and RenameRequired for sqlserver2014a.

        .EXAMPLE
            Test-DbaServerName -SqlInstance sqlserver2014a, sql2016

            Returns ServerInstanceName, SqlServerName, IsEqual and RenameRequired for sqlserver2014a and sql2016.

        .EXAMPLE
            Test-DbaServerName -SqlInstance sqlserver2014a, sql2016 -ExcludeSsrs

            Returns ServerInstanceName, SqlServerName, IsEqual and RenameRequired for sqlserver2014a and sql2016, but skips validating if SSRS is installed on both instances.

        .EXAMPLE
            Test-DbaServerName -SqlInstance sqlserver2014a, sql2016 | Select-Object *

            Returns ServerInstanceName, SqlServerName, IsEqual and RenameRequired for sqlserver2014a and sql2016.

            If a Rename is required, it will also show Updatable, and Reasons if the servername is not updatable.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.ArrayList])]
    param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [switch]$Detailed,
        [Alias("NoWarning")]
        [switch]$ExcludeSsrs,
        [switch][Alias('Silent')]$EnableException
    )

    begin {
        Test-DbaDeprecation -DeprecatedOn 1.0.0 -Parameter Detailed
        Test-DbaDeprecation -DeprecatedOn 1.0.0 -Parameter NoWarning
    }
    process {

        foreach ($instance in $SqlInstance) {
            Write-Verbose "Attempting to connect to $instance"
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($server.IsClustered) {
                Write-Message -Level Warning -Message  "$instance is a cluster. Renaming clusters is not supported by Microsoft."
            }

            $sqlInstanceName = $server.Query("SELECT @@servername AS ServerName").ServerName
            $instance = $server.InstanceName

            if ($instance.Length -eq 0) {
                $serverInstanceName = $server.NetName
                $instance = "MSSQLSERVER"
            }
            else {
                $netname = $server.NetName
                $serverInstanceName = "$netname\$instance"
            }

            $serverInfo = [PSCustomObject]@{
                ComputerName   = $server.NetName
                InstanceName   = $server.ServiceName
                SqlInstance    = $server.DomainInstanceName
                IsEqual        = $serverInstanceName -eq $sqlInstanceName
                RenameRequired = $serverInstanceName -ne $sqlInstanceName
                Updatable      = "N/A"
                Warnings       = $null
                Blockers       = $null
            }

            $reasons = @()
            $ssrsService = "SQL Server Reporting Services ($instance)"

            Write-Message -Level Verbose -Message "Checking for $serverName on $netBiosName"
            $rs = $null
            if ($SkipSsrs -eq $false -or $NoWarning -eq $false) {
                try {
                    $rs = Get-DbaSqlService -ComputerName $instance.ComputerName -Instance $server.ServiceName -Type SSRS -EnableException -WarningAction Stop
                }
                catch {
                    Write-Message -Level Warning -Message  "Unable to pull information on $ssrsService." -ErrorRecord $_ -Target $instance
                }
            }

            if ($null -ne $rs -or $rs.Count -gt 0) {
                if ($rs.State -eq 'Running') {
                    $rstext = "$ssrsService must be stopped and updated."
                }
                else {
                    $rstext = "$ssrsService exists. When it is started again, it must be updated."
                }
                $serverInfo.Warnings = $rstext
            }
            else {
                $serverInfo.Warnings = "N/A"
            }

            # check for mirroring
            $mirroredDb = $server.Databases | Where-Object { $_.IsMirroringEnabled -eq $true }

            Write-Debug "Found the following mirrored dbs: $($mirroredDb.Name)"

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
            $sql = "SELECT srl.remote_name as RemoteLoginName FROM sys.remote_logins srl JOIN sys.sysservers sss ON srl.server_id = sss.srvid"
            Write-Message -Level Debug -Message "SQL Statement: $sql"
            $results = $server.Query($sql)

            if ($results.RemoteLoginName.Count -gt 0) {
                $remoteLogins = $results.RemoteLoginName -join ", "
                $reasons += "Remote logins still exist: $remoteLogins"
            }

            if ($reasons.Length -gt 0) {
                $serverInfo.Updatable = $false
                $serverInfo.Blockers = $reasons
            }
            else {
                $serverInfo.Updatable = $true
                $serverInfo.Blockers = "N/A"
            }

            $serverInfo | Select-DefaultView -ExcludeProperty Warnings, Blockers
        }
    }
}