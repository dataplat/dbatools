function Measure-DbaBackupThroughput {
    <#
    .SYNOPSIS
        Determines how quickly SQL Server is backing up databases to media.

    .DESCRIPTION
        Returns backup history details for one or more databases on a SQL Server.

        Output looks like this:
        SqlInstance     : sql2016
        Database        : SharePoint_Config
        AvgThroughput   : 1.07 MB
        AvgSize         : 24.17
        AvgDuration     : 00:00:01.1000000
        MinThroughput   : 0.02 MB
        MaxThroughput   : 2.26 MB
        MinBackupDate   : 8/6/2015 10:22:01 PM
        MaxBackupDate   : 6/19/2016 12:57:45 PM
        BackupCount     : 10

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER Database
        The database(s) to process. Options for this list are auto-populated from the server. If unspecified, all databases will be processed.

    .PARAMETER ExcludeDatabase
        The database(s) to exclude. Options for this list are auto-populated from the server.

    .PARAMETER Type
        By default, this command measures the speed of Full backups. Valid options are "Full", "Log" and "Differential".

    .PARAMETER Since
        All backups taken on or after the point in time represented by this datetime object will be processed.

    .PARAMETER Last
        If this switch is enabled, only the last backup will be measured.

    .PARAMETER DeviceType
        Specifies one or more DeviceTypes to use in filtering backup sets. Valid values are "Disk", "Permanent Disk Device", "Tape", "Permanent Tape Device", "Pipe", "Permanent Pipe Device" and "Virtual Device", as well as custom integers for your own DeviceTypes.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Backup, Database
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Measure-DbaBackupThroughput

    .EXAMPLE
        PS C:\> Measure-DbaBackupThroughput -SqlInstance sql2016

        Parses every backup in msdb's backuphistory for stats on all databases.

    .EXAMPLE
        PS C:\> Measure-DbaBackupThroughput -SqlInstance sql2016 -Database AdventureWorks2014

        Parses every backup in msdb's backuphistory for stats on AdventureWorks2014.

    .EXAMPLE
        PS C:\> Measure-DbaBackupThroughput -SqlInstance sql2005 -Last

        Processes the last full, diff and log backups every backup for all databases on sql2005.

    .EXAMPLE
        PS C:\> Measure-DbaBackupThroughput -SqlInstance sql2005 -Last -Type Log

        Processes the last log backups every backup for all databases on sql2005.

    .EXAMPLE
        PS C:\> Measure-DbaBackupThroughput -SqlInstance sql2016 -Since (Get-Date).AddDays(-7) | Where-Object { $_.MinThroughput.Gigabyte -gt 1 }

        Gets backup calculations for the last week and filters results that have a minimum of 1GB throughput

    .EXAMPLE
        PS C:\> Measure-DbaBackupThroughput -SqlInstance sql2016 -Since (Get-Date).AddDays(-365) -Database bigoldb

        Gets backup calculations, limited to the last year and only the bigoldb database

    #>
    [CmdletBinding()]
    param (
        [parameter(Mandatory, ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [datetime]$Since,
        [switch]$Last,
        [ValidateSet("Full", "Log", "Differential", "File", "Differential File", "Partial Full", "Partial Differential")]
        [string]$Type = "Full",
        [string[]]$DeviceType,
        [switch]$EnableException
    )

    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            if ($Database) {
                $DatabaseCollection = $server.Databases | Where-Object Name -in $Database
            } else {
                $DatabaseCollection = $server.Databases
            }

            if ($ExcludeDatabase) {
                $DatabaseCollection = $DatabaseCollection | Where-Object Name -NotIn $ExcludeDatabase
            }

            foreach ($db in $DatabaseCollection) {
                Write-Message -Level VeryVerbose -Message "Retrieving history for $db."
                $allHistory = @()

                # Splatting didn't work
                if ($Since) {
                    $histories = Get-DbaDbBackupHistory -SqlInstance $server -Database $db.name -Since $Since -DeviceType $DeviceType -Type $Type
                } else {
                    $histories = Get-DbaDbBackupHistory -SqlInstance $server -Database $db.name -Last:$Last -DeviceType $DeviceType -Type $Type
                }

                foreach ($history in $histories) {
                    $timeTaken = New-TimeSpan -Start $history.Start -End $history.End

                    if ($timeTaken.TotalMilliseconds -eq 0) {
                        $throughput = $history.TotalSize.Megabyte
                    } else {
                        $throughput = $history.TotalSize.Megabyte / $timeTaken.TotalSeconds
                    }

                    Add-Member -Force -InputObject $history -MemberType NoteProperty -Name MBps -value $throughput

                    $allHistory += $history | Select-Object ComputerName, InstanceName, SqlInstance, Database, MBps, TotalSize, Start, End
                }

                Write-Message -Level VeryVerbose -Message "Calculating averages for $db."
                foreach ($db in ($allHistory | Sort-Object Database | Group-Object Database)) {

                    $measureMb = $db.Group.MBps | Measure-Object -Average -Minimum -Maximum
                    $measureStart = $db.Group.Start | Measure-Object -Minimum
                    $measureEnd = $db.Group.End | Measure-Object -Maximum
                    $measureSize = $db.Group.TotalSize.Megabyte | Measure-Object -Average
                    $avgDuration = $db.Group | ForEach-Object { New-TimeSpan -Start $_.Start -End $_.End } | Measure-Object -Average TotalSeconds

                    [PSCustomObject]@{
                        ComputerName  = $db.Group.ComputerName | Select-Object -First 1
                        InstanceName  = $db.Group.InstanceName | Select-Object -First 1
                        SqlInstance   = $db.Group.SqlInstance | Select-Object -First 1
                        Database      = $db.Name
                        AvgThroughput = [DbaSize]([System.Math]::Round($measureMb.Average, 2) * 1024 * 1024)
                        AvgSize       = [DbaSize]([System.Math]::Round($measureSize.Average, 2) * 1024 * 1024)
                        AvgDuration   = [DbaTimeSpan](New-TimeSpan -Seconds $avgDuration.Average)
                        MinThroughput = [DbaSize]([System.Math]::Round($measureMb.Minimum, 2) * 1024 * 1024)
                        MaxThroughput = [DbaSize]([System.Math]::Round($measureMb.Maximum, 2) * 1024 * 1024)
                        MinBackupDate = [DbaDateTime]$measureStart.Minimum
                        MaxBackupDate = [DbaDateTime]$measureEnd.Maximum
                        BackupCount   = $db.Count
                    }
                }
            }
        }
    }
}