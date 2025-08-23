function Invoke-DbaXEReplay {
    <#
    .SYNOPSIS
        Replays SQL queries captured in Extended Event files against target SQL Server instances

    .DESCRIPTION
        This command replays SQL workloads captured in Extended Event files against one or more target SQL Server instances for performance testing and load simulation. It extracts SQL statements from Extended Event data piped from Read-DbaXEFile and executes them sequentially against your specified targets.

        The function works by collecting SQL queries from the Extended Event stream, writing them to a temporary SQL file with proper batch separators, then executing the file using sqlcmd to ensure batches run correctly. This approach allows you to replay production workloads in test environments to validate performance changes, test capacity, or troubleshoot query behavior under realistic conditions.

        By default, it processes sql_batch_completed and rcp_completed events, but you can filter to specific event types. The replay maintains the original SQL structure while allowing you to redirect the workload to different databases or instances as needed.

    .PARAMETER SqlInstance
        Target SQL Server(s)

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

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
        Tags: ExtendedEvent, XE, XEvent
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Invoke-DbaXEReplay

    .EXAMPLE
        PS C:\> Read-DbaXEFile -Path C:\temp\sample.xel | Invoke-DbaXEReplay -SqlInstance sql2017

        Runs all batch_text for sql_batch_completed against tempdb on sql2017.

    .EXAMPLE
        PS C:\> Read-DbaXEFile -Path C:\temp\sample.xel | Invoke-DbaXEReplay -SqlInstance sql2017 -Database planning -Event sql_batch_completed

        Sets the *initial* database to planning then runs only sql_batch_completed against sql2017.

    .EXAMPLE
        PS C:\> Read-DbaXEFile -Path C:\temp\sample.xel | Invoke-DbaXEReplay -SqlInstance sql2017, sql2016

        Runs all batch_text for sql_batch_completed against tempdb on sql2017 and sql2016.


    #>
    [Cmdletbinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseOutputTypeCorrectly", "", Justification = "PSSA Rule Ignored by BOH")]
    param (
        [Parameter(Mandatory)]
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$Event = @('sql_batch_completed', 'rcp_completed'),
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]$InputObject,
        [switch]$Raw,
        [switch]$EnableException
    )

    begin {
        #Variable marked as unused by PSScriptAnalyzer
        #$querycolumns = 'statement', 'batch_text'
        $timestamp = (Get-Date -Format yyyyMMddHHmm)
        $temp = ([System.IO.Path]::GetTempPath()).TrimEnd("\")
        $filename = "$temp\dbatools-replay-$timestamp.sql"
        Set-Content $filename -Value $null

        if (-not (Get-Command sqlcmd -ErrorAction Ignore)) {
            Stop-Function -Message "sqlcmd is not installed. Please install the SQL Server Command Line Utilities."
            return
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
        } else {
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
                $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
            } catch {
                Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
            }


            if ($Raw) {
                Write-Message -Message "Invoking XEReplay against $instance running on $($server.name) with raw output" -Level Verbose
                if (Test-Bound -ParameterName SqlCredential) {
                    . sqlcmd -S $instance -i $filename -U $SqlCredential.Username -P $SqlCredential.GetNetworkCredential().Password
                    continue
                } else {
                    . sqlcmd -S $instance -i $filename
                    continue
                }
            }

            Write-Message -Message "Invoking XEReplay against $instance running on $($server.name)" -Level Verbose
            if (Test-Bound -ParameterName SqlCredential) {
                $output = . sqlcmd -S $instance -i $filename -U $SqlCredential.Username -P $SqlCredential.GetNetworkCredential().Password
            } else {
                $output = . sqlcmd -S $instance -i $filename
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