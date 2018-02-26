function Test-DbaVirtualLogFile {
    <#
        .SYNOPSIS
            Returns calculations on the database virtual log files for database on a SQL instance.

        .DESCRIPTION
            Having a transaction log file with too many virtual log files (VLFs) can hurt database performance.

            Too many VLFs can cause transaction log backups to slow down and can also slow down database recovery and, in extreme cases, even affect insert/update/delete performance.

            References:
                http://www.sqlskills.com/blogs/kimberly/transaction-log-vlfs-too-many-or-too-few/
                http://blogs.msdn.com/b/saponsqlserver/archive/2012/02/22/too-many-virtual-log-files-vlfs-can-cause-slow-database-recovery.aspx

            If you've got a high number of VLFs, you can use Expand-SqlTLogResponsibly to reduce the number.

        .PARAMETER SqlInstance
            Specifies the SQL Server instance(s) to scan.

        .PARAMETER SqlCredential
            Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

            $scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.

            Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

            To connect as a different Windows user, run PowerShell as that user.

        .PARAMETER Database
            Specifies the database(s) to process. Options for this list are auto-populated from the server. If unspecified, all databases will be processed.

        .PARAMETER ExcludeDatabase
            Specifies the database(s) to exclude from processing. Options for this list are auto-populated from the server.

        .PARAMETER IncludeSystemDBs
            If this switch is enabled, system database information will be displayed.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: VLF, Database

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .LINK
            https://dbatools.io/Test-DbaVirtualLogFile

        .EXAMPLE
            Test-DbaVirtualLogFile -SqlInstance sqlcluster

            Returns all user database virtual log file counts for the sqlcluster instance.

        .EXAMPLE
            Test-DbaVirtualLogFile -SqlInstance sqlserver | Where-Object {$_.Count -ge 50}

            Returns user databases that have 50 or more VLFs.

        .EXAMPLE
            @('sqlserver','sqlcluster') | Test-DbaVirtualLogFile

            Returns all VLF information for the sqlserver and sqlcluster SQL Server instances. Processes data via the pipeline.

        .EXAMPLE
            Test-DbaVirtualLogFile -SqlInstance sqlcluster -Database db1, db2

            Returns VLF counts for the db1 and db2 databases on sqlcluster.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.ArrayList])]
    param ([parameter(ValueFromPipeline, Mandatory = $true)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [Alias("Databases")]
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$IncludeSystemDBs,
        [switch][Alias('Silent')]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                Write-Message -Level Verbose -Message "Connecting to $instance."
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
            }
            catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            $dbs = $server.Databases
            if ($Database) {
                $dbs = $dbs | Where-Object Name -in $Database
            }
            if ($ExcludeDatabase) {
                $dbs = $dbs | Where-Object Name -NotIn $ExcludeDatabase
            }

            if (!$IncludeSystemDBs) {
                $dbs = $dbs | Where-Object IsSystemObject -eq $false
            }

            foreach ($db in $dbs) {
                try {
                    $data = Get-DbaDbVirtualLogFile -SqlInstance $server -Database $db.Name
                    $logFile = Get-DbaDatabaseFile -SqlInstance $server -Database $db.Name | Where-Object Type -eq 1

                    $active = $data | Where-Object Status -EQ 2
                    $inactive = $data | Where-Object Status -EQ 0

                    [PSCustomObject]@{
                        ComputerName      = $server.NetName
                        InstanceName      = $server.ServiceName
                        SqlInstance       = $server.DomainInstanceName
                        Database          = $db.name
                        Total             = $data.Count
                        TotalCount        = $data.Count
                        Inactive          = if ($inactive -and $null -eq $inactive.Count) {1} else {$inactive.Count}
                        Active            = if ($active -and $null -eq $active.Count) {1} else {$active.Count}
                        LogFileName       = $logFile.LogicalName -join ","
                        LogFileGrowth     = $logFile.Growth -join ","
                        LogFileGrowthType = $logFile.GrowthType -join ","
                    } | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, Database, Total
                }
                catch {
                    Stop-Function -Message "Unable to query $($db.name) on $instance." -ErrorRecord $_ -Target $db -Continue
                }
            }
        }
    }
}