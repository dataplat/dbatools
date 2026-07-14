function Measure-DbaDbVirtualLogFile {
    <#
    .SYNOPSIS
        Measures Virtual Log File (VLF) counts in transaction logs to identify performance bottlenecks

    .DESCRIPTION
        Analyzes Virtual Log File (VLF) fragmentation across databases by counting total, active, and inactive VLFs in transaction logs. This function helps identify databases with excessive VLF counts that can severely impact performance.

        High VLF counts (typically over 50-100) cause transaction log backups to slow down, extend database recovery times, and in extreme cases can affect insert/update/delete operations. This commonly happens when transaction logs auto-grow frequently in small increments rather than being pre-sized appropriately.

        The function returns VLF counts along with log file growth settings, making it easy to spot databases that need log file maintenance. Use this for regular health checks, performance troubleshooting, or before major maintenance windows.

        References:
        http://www.sqlskills.com/blogs/kimberly/transaction-log-vlfs-too-many-or-too-few/
        http://blogs.msdn.com/b/saponsqlserver/archive/2012/02/22/too-many-virtual-log-files-vlfs-can-cause-slow-database-recovery.aspx

        If you've got a high number of VLFs, you can use Expand-SqlTLogResponsibly to reduce the number.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to analyze for VLF counts. Accepts database names, wildcards, or arrays of database names.
        Use this to focus VLF analysis on specific databases when troubleshooting performance issues or during targeted maintenance.

    .PARAMETER ExcludeDatabase
        Specifies databases to skip during VLF analysis. Accepts database names, wildcards, or arrays of database names.
        Use this to exclude problematic databases or those you know are healthy when running instance-wide VLF checks.

    .PARAMETER IncludeSystemDBs
        Includes system databases (master, model, msdb, tempdb) in the VLF analysis.
        By default only user databases are analyzed since system database VLF counts are typically less critical for performance tuning.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Diagnostic, VLF, LogFile
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Measure-DbaDbVirtualLogFile

    .OUTPUTS
        PSCustomObject

        Returns one object per database containing virtual log file (VLF) statistics and transaction log growth configuration.

        Default display properties (via Select-DefaultView):
        - ComputerName: The computer name of the SQL Server instance
        - InstanceName: The SQL Server instance name
        - SqlInstance: The full SQL Server instance name (computer\instance)
        - Database: Name of the database
        - Total: Total count of VLFs in the transaction log

        Additional properties available:
        - TotalCount: Duplicate of Total (total count of VLFs)
        - Inactive: Count of inactive VLFs (status = 0)
        - Active: Count of active VLFs (status = 2)
        - LogFileName: Comma-separated list of logical names of the transaction log files
        - LogFileGrowth: Comma-separated list of growth increment values for each log file
        - LogFileGrowthType: Comma-separated list of growth types (Percent or kb) for each log file

        Use Select-Object * to access all properties.

    .EXAMPLE
        PS C:\> Measure-DbaDbVirtualLogFile -SqlInstance sqlcluster

        Returns all user database virtual log file counts for the sqlcluster instance.

    .EXAMPLE
        PS C:\> Measure-DbaDbVirtualLogFile -SqlInstance sqlserver | Where-Object {$_.Total -ge 50}

        Returns user databases that have 50 or more VLFs.

    .EXAMPLE
        PS C:\> @('sqlserver','sqlcluster') | Measure-DbaDbVirtualLogFile

        Returns all VLF information for the sqlserver and sqlcluster SQL Server instances. Processes data via the pipeline.

    .EXAMPLE
        PS C:\> Measure-DbaDbVirtualLogFile -SqlInstance sqlcluster -Database db1, db2

        Returns VLF counts for the db1 and db2 databases on sqlcluster.

    #>
    [CmdletBinding()]
    [OutputType([System.Collections.ArrayList])]
    param ([parameter(ValueFromPipeline, Mandatory)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [switch]$IncludeSystemDBs,
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
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
                    $logFile = Get-DbaDbFile -SqlInstance $server -Database $db.Name | Where-Object Type -eq 1

                    $active = $data | Where-Object Status -eq 2
                    $inactive = $data | Where-Object Status -eq 0

                    [PSCustomObject]@{
                        ComputerName      = $server.ComputerName
                        InstanceName      = $server.ServiceName
                        SqlInstance       = $server.DomainInstanceName
                        Database          = $db.name
                        Total             = $data.Count
                        TotalCount        = $data.Count
                        Inactive          = if ($inactive -and $null -eq $inactive.Count) { 1 } else { $inactive.Count }
                        Active            = if ($active -and $null -eq $active.Count) { 1 } else { $active.Count }
                        LogFileName       = $logFile.LogicalName -join ","
                        LogFileGrowth     = $logFile.Growth -join ","
                        LogFileGrowthType = $logFile.GrowthType -join ","
                    } | Select-DefaultView -Property ComputerName, InstanceName, SqlInstance, Database, Total
                } catch {
                    Stop-Function -Message "Unable to query $($db.name) on $instance." -ErrorRecord $_ -Target $db -Continue
                }
            }
        }
    }
}