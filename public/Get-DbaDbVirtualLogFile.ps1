
function Get-DbaDbVirtualLogFile {
    <#
    .SYNOPSIS
        Retrieves detailed virtual log file (VLF) metadata from transaction logs for performance analysis and troubleshooting.

    .DESCRIPTION
        This function uses DBCC LOGINFO to return detailed metadata about each virtual log file (VLF) within database transaction logs. The output includes VLF size, file offsets, sequence numbers, status, and parity information that's essential for analyzing transaction log structure and performance.

        Having a transaction log file with too many virtual log files (VLFs) can hurt database performance. Too many VLFs can cause transaction log backups to slow down and can also slow down database recovery and, in extreme cases, even affect insert/update/delete performance.

        Common use cases include identifying databases with excessive VLF counts (typically over 50-100), analyzing VLF size distribution to spot fragmentation issues, and monitoring VLF status during active transactions. This data helps DBAs make informed decisions about log file growth settings and maintenance schedules.

        References:
        http://www.sqlskills.com/blogs/kimberly/transaction-log-vlfs-too-many-or-too-few/
        http://blogs.msdn.com/b/saponsqlserver/archive/2012/02/22/too-many-virtual-log-files-vlfs-can-cause-slow-database-recovery.aspx

        If you've got a high number of VLFs, you can use Expand-DbaDbLogFile to reduce the number.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        Specifies which databases to analyze for VLF information. Accepts wildcards for pattern matching.
        Use this when you need to focus on specific databases instead of checking all databases on the instance.

    .PARAMETER ExcludeDatabase
        Specifies which databases to skip during VLF analysis. Accepts wildcards for pattern matching.
        Use this to exclude problematic databases or those you don't need to monitor for VLF issues.

    .PARAMETER IncludeSystemDBs
        Include system databases (master, model, msdb, tempdb) in the VLF analysis.
        By default, only user databases are checked since system database VLF counts are typically less critical for performance tuning.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .OUTPUTS
        PSCustomObject

        Returns one object per virtual log file (VLF) found in each database transaction log.

        Properties:
        - ComputerName: The name of the computer hosting the SQL Server instance
        - InstanceName: The name of the SQL Server instance
        - SqlInstance: The full SQL Server instance name (ComputerName\InstanceName)
        - Database: The name of the database containing the virtual log file
        - RecoveryUnitId: The recovery unit identifier for the VLF
        - FileId: The transaction log file ID (typically 0 for the primary log file)
        - FileSize: The size of the virtual log file in bytes
        - StartOffset: The starting offset of this VLF within the transaction log file in bytes
        - FSeqNo: The virtual log file sequence number - indicates the order of VLFs in the transaction log
        - Status: The status of the VLF (0=unused, 1=active, 2=recoverable)
        - Parity: The parity value used for recovery tracking and alternate backup validation
        - CreateLsn: The Log Sequence Number (LSN) at which this VLF was created

    .NOTES
        Tags: Diagnostic, VLF, Database, LogFile
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDbVirtualLogFile

    .EXAMPLE
        PS C:\> Get-DbaDbVirtualLogFile -SqlInstance sqlcluster

        Returns all user database virtual log file details for the sqlcluster instance.

    .EXAMPLE
        PS C:\> Get-DbaDbVirtualLogFile -SqlInstance sqlserver | Group-Object -Property Database | Where-Object Count -gt 50

        Returns user databases that have 50 or more VLFs.

    .EXAMPLE
        PS C:\> 'sqlserver','sqlcluster' | Get-DbaDbVirtualLogFile

        Returns all VLF information for the sqlserver and sqlcluster SQL Server instances. Processes data via the pipeline.

    .EXAMPLE
        PS C:\> Get-DbaDbVirtualLogFile -SqlInstance sqlcluster -Database db1, db2

        Returns the VLF counts for the db1 and db2 databases on sqlcluster.

    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
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

            $dbs = $server.Databases | Where-Object IsAccessible

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
                    $data = $db.Query("DBCC LOGINFO")

                    foreach ($d in $data) {
                        [PSCustomObject]@{
                            ComputerName   = $server.ComputerName
                            InstanceName   = $server.ServiceName
                            SqlInstance    = $server.DomainInstanceName
                            Database       = $db.Name
                            RecoveryUnitId = $d.RecoveryUnitId
                            FileId         = $d.FileId
                            FileSize       = $d.FileSize
                            StartOffset    = $d.StartOffset
                            FSeqNo         = $d.FSeqNo
                            Status         = $d.Status
                            Parity         = $d.Parity
                            CreateLsn      = $d.CreateLSN
                        }
                    }
                } catch {
                    Stop-Function -Message "Unable to query $($db.name) on $instance." -ErrorRecord $_ -Target $db -Continue
                }
            }
        }
    }
}