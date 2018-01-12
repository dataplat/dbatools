function Measure-DbaBackupThroughput {
    <#
        .SYNOPSIS
            Determines how quickly SQL Server is backing up databases to media.

        .DESCRIPTION
            Returns backup history details for one or more databases on a SQL Server.

            Output looks like this:
            SqlInstance     : sql2016
            Database        : SharePoint_Config
            AvgThroughputMB : 1.07
            AvgSizeMB       : 24.17
            AvgDuration     : 00:00:01.1000000
            MinThroughputMB : 0.02
            MaxThroughputMB : 2.26
            MinBackupDate   : 8/6/2015 10:22:01 PM
            MaxBackupDate   : 6/19/2016 12:57:45 PM
            BackupCount     : 10

        .PARAMETER SqlInstance
            The SQL Server instance.

        .PARAMETER SqlCredential
            Allows you to login to servers using SQL Logins instead of Windows Authentication (AKA Integrated or Trusted). To use:

            $scred = Get-Credential, then pass $scred object to the -SqlCredential parameter.

            Windows Authentication will be used if SqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials.

            To connect as a different Windows user, run PowerShell as that user.

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
            Tags: DisasterRecovery, Backup, Databases

            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

        .LINK
            https://dbatools.io/Measure-DbaBackupThroughput

        .EXAMPLE
            Measure-DbaBackupThroughput -SqlInstance sql2016

            Parses every backup in msdb's backuphistory for stats on all databases.

        .EXAMPLE
            Measure-DbaBackupThroughput -SqlInstance sql2016 -Database AdventureWorks2014

            Parses every backup in msdb's backuphistory for stats on AdventureWorks2014.

        .EXAMPLE
            Measure-DbaBackupThroughput -SqlInstance sql2005 -Last

            Processes the last full, diff and log backups every backup for all databases on sql2005.

        .EXAMPLE
            Measure-DbaBackupThroughput -SqlInstance sql2005 -Last -Type Log

            Processes the last log backups every backup for all databases on sql2005.

        .EXAMPLE
            Measure-DbaBackupThroughput -SqlInstance sql2016 -Since (Get-Date).AddDays(-7)

            Gets backup calculations for the last week.

        .EXAMPLE
            Measure-DbaBackupThroughput -SqlInstance sql2016 -Since (Get-Date).AddDays(-365) -Database bigoldb

            Gets backup calculations, limited to the last year and only the bigoldb database

    #>
    [CmdletBinding()]
    param (
        [parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
        [Alias("ServerInstance", "Instance", "SqlServer")]
        [DbaInstanceParameter[]]$SqlInstance,
        [Alias("Credential")]
        [PSCredential]$SqlCredential,
        [Alias("Databases")]
        [object[]]$Database,
        [object[]]$ExcludeDatabase,
        [datetime]$Since,
        [switch]$Last,
        [ValidateSet("Full", "Log", "Differential", "File", "Differential File", "Partial Full", "Partial Differential")]
        [string]$Type = "Full",
        [string[]]$DeviceType,
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

            if ($Database) {
                $DatabaseCollection = $server.Databases | Where-Object Name -in $Database
            }
            else {
                $DatabaseCollection = $server.Databases
            }

            if ($ExcludeDatabase) {
                $DatabaseCollection = $DatabaseCollection | Where-Object Name -NotIn $ExcludeDatabase
            }

            foreach ($db in $DatabaseCollection) {
                Write-Message -Level VeryVerbose -Message "Retrieving history for $db."
                $allhistory = @()

                # Splatting didn't work
                if ($since) {
                    $histories = Get-DbaBackupHistory -SqlInstance $server -Database $db.name -Since $since -DeviceType $DeviceType -Type $Type
                }
                else {
                    $histories = Get-DbaBackupHistory -SqlInstance $server -Database $db.name -Last:$last -DeviceType $DeviceType -Type $Type
                }

                foreach ($history in $histories) {
                    $timetaken = New-TimeSpan -Start $history.Start -End $history.End

                    if ($timetaken.TotalMilliseconds -eq 0) {
                        $throughput = $history.TotalSize.Megabyte
                    }
                    else {
                        $throughput = $history.TotalSize.Megabyte / $timetaken.TotalSeconds
                    }

                    Add-Member -Force -InputObject $history -MemberType Noteproperty -Name MBps -value $throughput

                    $allhistory += $history | Select-Object ComputerName, InstanceName, SqlInstance, Database, MBps, TotalSize, Start, End
                }

                Write-Message -Level VeryVerbose -Message "Calculating averages for $db."
                foreach ($db in ($allhistory | Sort-Object Database | Group-Object Database)) {

                    $measuremb = $db.Group.MBps | Measure-Object -Average -Minimum -Maximum
                    $measurestart = $db.Group.Start | Measure-Object -Minimum
                    $measureend = $db.Group.End | Measure-Object -Maximum
                    $measuresize = $db.Group.TotalSize.Megabyte | Measure-Object -Average
                    $avgduration = $db.Group | ForEach-Object { New-TimeSpan -Start $_.Start -End $_.End } | Measure-Object -Average TotalSeconds

                    [pscustomobject]@{
                        ComputerName    = $db.Group.ComputerName | Select-Object -First 1
                        InstanceName    = $db.Group.InstanceName | Select-Object -First 1
                        SqlInstance     = $db.Group.SqlInstance | Select-Object -First 1
                        Database        = $db.Name
                        AvgThroughputMB = [System.Math]::Round($measuremb.Average, 2)
                        AvgSizeMB       = [System.Math]::Round($measuresize.Average, 2)
                        AvgDuration     = [dbatimespan](New-TimeSpan -Seconds $avgduration.Average)
                        MinThroughputMB = [System.Math]::Round($measuremb.Minimum, 2)
                        MaxThroughputMB = [System.Math]::Round($measuremb.Maximum, 2)
                        MinBackupDate   = [dbadatetime]$measurestart.Minimum
                        MaxBackupDate   = [dbadatetime]$measureend.Maximum
                        BackupCount     = $db.Count
                    } | Select-DefaultView -ExcludeProperty ComputerName, InstanceName
                }
            }
        }
    }
}
