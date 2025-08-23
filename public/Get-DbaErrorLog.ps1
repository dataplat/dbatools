function Get-DbaErrorLog {
    <#
    .SYNOPSIS
        Retrieves SQL Server error log entries for troubleshooting and monitoring

    .DESCRIPTION
        Retrieves entries from SQL Server error logs across all available log files (0-99, where 0 is current and 99 is oldest).
        Essential for troubleshooting SQL Server issues, monitoring login failures, tracking system events, and compliance auditing.
        Supports filtering by log number, source type, text patterns, and date ranges to quickly locate specific errors or events.
        Reads from all available error logs by default, so you don't have to check each log file manually.

    .PARAMETER SqlInstance
        The target SQL Server instance or instances.

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

    .PARAMETER LogNumber
        Specifies which error log file to read by index number (0-99), where 0 is the current active log and higher numbers are older archived logs.
        Use this to target specific log files when troubleshooting issues from a particular time period or to avoid reading all logs for performance.
        SQL Server keeps 6 log files by default but can be configured up to 99 archived logs.

    .PARAMETER Source
        Filters log entries by the source component that generated the message, such as "Logon", "Server", "Backup", or "spid123".
        Use this to focus on specific SQL Server subsystems when troubleshooting authentication issues, backup problems, or tracking activity from particular processes.

    .PARAMETER Text
        Searches for log entries containing specific text patterns using wildcard matching (supports * wildcards).
        Use this to find specific error messages, user names, database names, or any text string within log entries for targeted troubleshooting.

    .PARAMETER After
        Returns only log entries that occurred after the specified date and time.
        Use this to focus on recent events or investigate issues that started after a known point in time, such as after a deployment or configuration change.

    .PARAMETER Before
        Returns only log entries that occurred before the specified date and time.
        Use this to investigate historical issues, exclude recent events from analysis, or focus on problems that existed prior to a specific incident or change.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Logging, Instance, ErrorLog
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaErrorLog

    .EXAMPLE
        PS C:\> Get-DbaErrorLog -SqlInstance sql01\sharepoint

        Returns every log entry from sql01\sharepoint SQL Server instance.

    .EXAMPLE
        PS C:\> Get-DbaErrorLog -SqlInstance sql01\sharepoint -LogNumber 3, 6

        Returns all log entries for log number 3 and 6 on sql01\sharepoint SQL Server instance.

    .EXAMPLE
        PS C:\> Get-DbaErrorLog -SqlInstance sql01\sharepoint -Source Logon

        Returns every log entry, with a source of Logon, from sql01\sharepoint SQL Server instance.

    .EXAMPLE
        PS C:\> Get-DbaErrorLog -SqlInstance sql01\sharepoint -LogNumber 3 -Text "login failed"

        Returns every log entry for log number 3, with "login failed" in the text, from sql01\sharepoint SQL Server instance.

    .EXAMPLE
        PS C:\> $servers = "sql2014","sql2016", "sqlcluster\sharepoint"
        PS C:\> $servers | Get-DbaErrorLog -LogNumber 0

        Returns the most recent SQL Server error logs for "sql2014","sql2016" and "sqlcluster\sharepoint"

    .EXAMPLE
        PS C:\> Get-DbaErrorLog -SqlInstance sql01\sharepoint -After '2016-11-14 00:00:00'

        Returns every log entry found after the date 14 November 2016 from sql101\sharepoint SQL Server instance.

    .EXAMPLE
        PS C:\> Get-DbaErrorLog -SqlInstance sql01\sharepoint -Before '2016-08-16 00:00:00'

        Returns every log entry found before the date 16 August 2016 from sql101\sharepoint SQL Server instance.

    #>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [ValidateRange(0, 99)]
        [int[]]$LogNumber,
        [object[]]$Source,
        [string]$Text,
        [datetime]$After,
        [datetime]$Before,
        [switch]$EnableException
    )
    process {
        foreach ($instance in $SqlInstance) {
            try {
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }

            # .ReadErrorLog() only reads active log.
            # As there is no detailed documentation, not clear if bug or feature.
            # https://docs.microsoft.com/en-us/dotnet/api/microsoft.sqlserver.management.smo.server.readerrorlog
            # Since the reading of non existing logs is lightning fast, we just read all possible logs.
            # Since the order inside of a log is from old to new, we read from 99 to 0.
            if (Test-Bound -Not -ParameterName LogNumber) {
                $LogNumber = 99 .. 0
            }

            foreach ($number in $lognumber) {
                foreach ($object in $server.ReadErrorLog($number)) {
                    if ( ($Source -and $object.ProcessInfo -ne $Source) -or ($Text -and $object.Text -notlike "*$Text*") -or ($After -and $object.LogDate -lt $After) -or ($Before -and $object.LogDate -gt $Before) ) {
                        continue
                    }
                    Write-Message -Level Verbose -Message "Processing $object"
                    Add-Member -Force -InputObject $object -MemberType NoteProperty ComputerName -value $server.ComputerName
                    Add-Member -Force -InputObject $object -MemberType NoteProperty InstanceName -value $server.ServiceName
                    Add-Member -Force -InputObject $object -MemberType NoteProperty SqlInstance -value $server.DomainInstanceName

                    # Select all of the columns you'd like to show
                    Select-DefaultView -InputObject $object -Property ComputerName, InstanceName, SqlInstance, LogDate, 'ProcessInfo as Source', Text
                }
            }
        }
    }
}