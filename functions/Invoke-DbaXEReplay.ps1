#ValidationTags#Messaging,FlowControl,Pipeline,CodeStyle#
function Invoke-DbaXeReplay {
    <#
        .SYNOPSIS
            This command replays events from Read-DbaXEFile on one or more target servers

        .DESCRIPTION
            This command replays events from Read-DbaXEFile. It is simplistic in its approach.
    
            - Writes all queries to a temp sql file
            - Executes temp file using sqlcmd so that batches are executed properly
            - Deletes temp file

        .PARAMETER SqlInstance
            Target SQL Server(s)

        .PARAMETER SqlCredential
            Used to provide alternative credentials.

        .PARAMETER Database
            The initial starting database.

        .PARAMETER Event
            Each Response can be limited to processing specific events, while ignoring all the other ones. When this attribute is omitted, all events are processed.

        .PARAMETER Raw
            By dafault, the results of sqlcmd are collected, cleaned up and displayed. If you'd like to see all results immeidately, use Raw.
    
        .PARAMETER InputObject
            Accepts the object output of Read-DbaXESession.

        .PARAMETER EnableException
            By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
            This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
            Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

        .NOTES
            Tags: ExtendedEvent, XE, Xevent
            Website: https://dbatools.io
            Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
            License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0
    
        .EXAMPLE
            Read-DbaXEFile -Path C:\temp\sample.xel | Invoke-DbaXeReplay -SqlInstance sql2017

            Runs all batch_text for sql_batch_completed against tempdb on sql2017.
        
        .EXAMPLE
            Read-DbaXEFile -Path C:\temp\sample.xel | Invoke-DbaXeReplay -SqlInstance sql2017 -Database planning -Event sql_batch_completed

            Sets the *initial* database to planning then runs only sql_batch_completed against sql2017.

        .EXAMPLE
            Read-DbaXEFile -Path C:\temp\sample.xel | Invoke-DbaXeReplay -SqlInstance sql2017, sql2016

            Runs all batch_text for sql_batch_completed against tempdb on sql2017 and sql2016

    #>
    Param (
        [Parameter(Mandatory)]
        [Alias("ServerInstance", "SqlServer")]
        [DbaInstance[]]$SqlInstance,
        [Alias("Credential")]
        [PsCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$Event = @('sql_batch_completed', 'rcp_completed'),
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]$InputObject,
        [switch]$Raw,
        [switch]$EnableException
    )
    
    begin {
        $querycolumns = 'statement', 'batch_text'
        $timestamp = (Get-Date -Format yyyyMMddHHmm)
        $temp = ([System.IO.Path]::GetTempPath()).TrimEnd("\")
        $filename = "$temp\dbatools-replay-$timestamp.sql"
        Set-Content $filename -Value $null
        
        if (-not (Get-Command sqlcmd -ErrorAction SilentlyContinue)) {
            Stop-Function -Message "sqlcmd is required but does not exist on this machine. We've asked Microsoft if we can include it in dbatools and are currently awaiting a response."
        }
    }
    process {
        if (Test-FunctionInterrupt) { return }
        if ($InputObject.Name -notin $Event) {
            continue
        }
        
        if ($InputObject.statement) {
            if ($InputObject.statement -notmatch "ALTER EVENT SESSION") {
                Add-Content -Path $filename -Value $InputObject.statement
                Add-Content -Path $filename -Value "GO"
            }
        }
        else {
            if ($InputObject.batch_text -notmatch "ALTER EVENT SESSION") {
                Add-Content -Path $filename -Value $InputObject.batch_text
                Add-Content -Path $filename -Value "GO"
            }
        }
    }
    end {
        if (Test-FunctionInterrupt) { return }
        foreach ($instance in $SqlInstance) {
            try {
                Write-Message -Level VeryVerbose -Message "Connecting to $instance." -Target $instance
                $server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
            }
            catch {
                Stop-Function -Message "Failure" -ErrorRecord $_ -Target $instance -Continue
            }
            
            
            if ($Raw) {
                if (Test-Bound -ParameterName SqlCredential) {
                    sqlcmd -S $instance -i $filename -U $SqlCredential.Username -P $SqlCredential.GetNetworkCredential().Password
                    continue
                }
                else {
                    sqlcmd -S $instance -i $filename
                    continue
                }
            }
            
            if (Test-Bound -ParameterName SqlCredential) {
                $output = sqlcmd -S $instance -i $filename -U $SqlCredential.Username -P $SqlCredential.GetNetworkCredential().Password
            }
            else {
                $output = sqlcmd -S $instance -i $filename
            }
            
            foreach ($line in $output) {
                $newline = $line.Trim()
                if ($newline -and $newline -notmatch "------------------------------------------------------------------------------------") {
                    "$newline"
                }
            }
        }
        Remove-Item -Path $filename -ErrorAction Ignore
    }
}