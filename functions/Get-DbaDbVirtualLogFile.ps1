#ValidationTags#CodeStyle,Messaging,FlowControl,Pipeline#
function Get-DbaDbVirtualLogFile {
    <#
        .SYNOPSIS
            Returns database virtual log file information for database files on a SQL instance.

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
            Login to the target instance using alternative credentials. Windows and SQL Authentication supported. Accepts credential objects (Get-Credential)

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
            Tags: VLF, Database, LogFile

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: MIT https://opensource.org/licenses/MIT

        .LINK
            https://dbatools.io/Get-DbaDbVirtualLogFile

        .EXAMPLE
            Get-DbaDbVirtualLogFile -SqlInstance sqlcluster

            Returns all user database virtual log file details for the sqlcluster instance.

        .EXAMPLE
            Get-DbaDbVirtualLogFile -SqlInstance sqlserver | Group-Object -Property Database | Where-Object Count -gt 50

            Returns user databases that have 50 or more VLFs.

        .EXAMPLE
            @('sqlserver','sqlcluster') | Get-DbaDbVirtualLogFile

            Returns all VLF information for the sqlserver and sqlcluster SQL Server instances. Processes data via the pipeline.

        .EXAMPLE
            Get-DbaDbVirtualLogFile -SqlInstance sqlcluster -Database db1, db2

            Returns the VLF counts for the db1 and db2 databases on sqlcluster.
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
        [Alias('Silent')]
        [switch]$EnableException
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
                        [pscustomobject]@{
                            ComputerName   = $server.NetName
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
                }
                catch {
                    Stop-Function -Message "Unable to query $($db.name) on $instance." -ErrorRecord $_ -Target $db -Continue
                }
            }
        }
    }
}
