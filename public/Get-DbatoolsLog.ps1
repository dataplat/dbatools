function Get-DbatoolsLog {
    <#
    .SYNOPSIS
        Retrieves internal log entries and error messages from dbatools module execution

    .DESCRIPTION
        Retrieves log entries from dbatools' internal logging system, allowing you to troubleshoot command execution and track what happened during script runs. Use this when dbatools commands aren't behaving as expected or when you need to see detailed execution information for debugging purposes. The function can filter logs by specific functions, modules, targets, execution history, or message levels, making it easier to isolate issues during SQL Server automation tasks.

    .PARAMETER FunctionName
        Filters log entries to show only messages from dbatools functions matching this pattern. Supports wildcards.
        Use this when troubleshooting specific commands like 'Backup-DbaDatabase' or when you want to see all backup-related functions with 'Backup-Dba*'.

    .PARAMETER ModuleName
        Filters log entries to show only messages from modules matching this pattern. Supports wildcards.
        Use this when working with multiple PowerShell modules and you only want to see dbatools-related log entries.

    .PARAMETER Target
        Filters log entries to show only messages related to a specific target object like a server name, database name, or other SQL Server component.
        Use this when troubleshooting issues with a particular SQL Server instance or database to see only relevant log entries.

    .PARAMETER Tag
        Filters log entries to show only messages that contain any of the specified tags.
        Use this to find specific types of operations like 'backup', 'restore', or 'migration' when tracking down issues with particular dbatools workflows.

    .PARAMETER Last
        Returns log entries from only the last X PowerShell command executions in your current session.
        Use this to focus on recent activity when troubleshooting the most recent dbatools commands you ran. Excludes Get-DbatoolsLog commands from the execution count to avoid confusion.

    .PARAMETER LastError
        Returns only the most recent error message from the dbatools logging system.
        Use this as a quick way to see what went wrong with your last dbatools command execution without scrolling through all log entries.

    .PARAMETER Skip
        Specifies how many recent executions to skip when using the -Last parameter.
        Use this when you want to see log entries from earlier executions, like '-Last 3 -Skip 2' to see the 3rd, 4th, and 5th most recent executions.

    .PARAMETER Raw
        Returns log messages in their original format without flattening multiline content like SQL statements.
        Use this when you need to see the exact formatting of SQL queries or error messages for detailed troubleshooting.

    .PARAMETER Runspace
        Filters log entries to show only messages from the specified PowerShell runspace GUID.
        Use this when troubleshooting parallel or background dbatools operations to isolate messages from specific execution threads.

    .PARAMETER Level
        Filters log entries by message severity level (Critical, Error, Warning, Info, Verbose, etc.).
        Use this to focus on specific severity levels, like only errors and warnings, or to see verbose details during troubleshooting. Supports arrays and ranges like (1..6).

    .PARAMETER Errors
        Returns error entries from dbatools' error tracking system instead of regular log entries.
        Use this when you specifically need to see exceptions and errors that occurred during dbatools command execution, separate from informational logging.

    .NOTES
        Tags: Module, Support
        Author: Friedrich Weinmann (@FredWeinmann)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbatoolsLog

    .OUTPUTS
        Dataplat.Dbatools.Message.LogEntry (when -Raw is specified)

        Returns raw internal LogEntry objects from the dbatools logging system without any property filtering or flattening of multiline content.

        PSCustomObject (default)

        Returns log entries with the following properties formatted for user display:

        - CallStack: The PowerShell call stack at the point the log entry was created
        - ComputerName: The name of the computer where the log entry was generated
        - File: The PowerShell script file name where the log entry originated
        - FunctionName: The name of the dbatools function that created the log entry
        - Level: The severity level of the log message (Critical, Error, Warning, Info, Verbose, Debug, etc.)
        - Line: The line number in the script file where the log entry was generated
        - Message: The log message text with multiline content (SQL statements, multiline errors) flattened to single line by joining with spaces and collapsing multiple spaces
        - ModuleName: The name of the module that generated the log entry (typically "dbatools")
        - Runspace: The PowerShell runspace GUID in which the log entry was created
        - Tags: Array of tag strings associated with the log entry for categorization (e.g., "backup", "restore", "connection")
        - TargetObject: The SQL Server object being processed when the log entry was created (e.g., server name, database name)
        - Timestamp: The DateTime when the log entry was created
        - Type: The type of log entry (Information, Error, Warning, etc.)
        - Username: The username of the person executing the command that generated the log entry

        Note: Use -Raw to return unmodified LogEntry objects with Message content preserved in original multiline format for detailed troubleshooting of SQL statements.

    .EXAMPLE
        PS C:\> Get-DbatoolsLog

        Returns all log entries currently in memory.

    .EXAMPLE
        PS C:\> Get-DbatoolsLog -LastError

        Returns the last log entry type of error.

    .EXAMPLE
        PS C:\> Get-DbatoolsLog -Target "a" -Last 1 -Skip 1

        Returns all log entries that targeted the object "a" in the second last execution sent.

    .EXAMPLE
        PS C:\> Get-DbatoolsLog -Tag "fail" -Last 5

        Returns all log entries within the last 5 executions that contained the tag "fail"
    #>
    [CmdletBinding()]
    param (
        [string]$FunctionName = "*",
        [string]$ModuleName = "*",
        [AllowNull()]
        [object]$Target,
        [string[]]$Tag,
        [int]$Last,
        [switch]$LastError,
        [int]$Skip = 0,
        [guid]$Runspace,
        [Dataplat.Dbatools.Message.MessageLevel[]]$Level,
        [switch]$Raw,
        [switch]$Errors
    )
    process {
        if ($Errors) {
            $messages = [Dataplat.Dbatools.Message.LogHost]::GetErrors() | Where-Object {
                ($_.FunctionName -like $FunctionName) -and ($_.ModuleName -like $ModuleName)
            }
        } else {
            $messages = [Dataplat.Dbatools.Message.LogHost]::GetLog() | Where-Object {
                ($_.FunctionName -like $FunctionName) -and ($_.ModuleName -like $ModuleName)
            }
        }

        if (Test-Bound -ParameterName LastError) {
            $messages = [Dataplat.Dbatools.Message.LogHost]::GetErrors() | Where-Object { ($_.FunctionName -like $FunctionName) -and ($_.ModuleName -like $ModuleName) } | Select-Object -Last 1
        }

        if (Test-Bound -ParameterName Target) {
            $messages = $messages | Where-Object TargetObject -eq $Target
        }

        if (Test-Bound -ParameterName Tag) {
            $messages = $messages | Where-Object {
                $_.Tags | Where-Object {
                    $_ -in $Tag
                }
            }
        }

        if (Test-Bound -ParameterName Runspace) {
            $messages = $messages | Where-Object Runspace -eq $Runspace
        }

        if (Test-Bound -ParameterName Last) {
            $history = Get-History | Where-Object CommandLine -NotLike "Get-DbatoolsLog*" | Select-Object -Last $Last -Skip $Skip
            $start = $history[0].StartExecutionTime
            $end = $history[-1].EndExecutionTime

            $messages = $messages | Where-Object {
                ($_.Timestamp -gt $start) -and ($_.Timestamp -lt $end) -and ($_.Runspace -eq ([System.Management.Automation.Runspaces.Runspace]::DefaultRunspace.InstanceId))
            }
        }

        if (Test-Bound -ParameterName Level) {
            $messages = $messages | Where-Object Level -In $Level
        }

        if ($Raw) {
            return $messages
        } else {
            $messages | Select-Object -Property CallStack, ComputerName, File, FunctionName, Level, Line, @{
                Name       = "Message"
                Expression = {
                    $msg = ($_.Message.Split("`n") -join " ")
                    do {
                        $msg = $msg.Replace('  ', ' ')
                    } until ($msg -notmatch '  ')
                    $msg
                }
            }, ModuleName, Runspace, Tags, TargetObject, Timestamp, Type, Username
        }
    }
}