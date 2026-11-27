function Invoke-DbaXEReplay {
    <#
    .SYNOPSIS
        Replays SQL queries captured in Extended Event files against target SQL Server instances

    .DESCRIPTION
        This command replays SQL workloads captured in Extended Event files against one or more target SQL Server instances for performance testing and load simulation. It extracts SQL statements from Extended Event data piped from Read-DbaXEFile and executes them sequentially against your specified targets.

        The function works by collecting SQL queries from the Extended Event stream, writing them to a temporary SQL file with proper batch separators, then executing the file using sqlcmd to ensure batches run correctly. This approach allows you to replay production workloads in test environments to validate performance changes, test capacity, or troubleshoot query behavior under realistic conditions.

        By default, it processes sql_batch_completed and rpc_completed events, but you can filter to specific event types. The replay maintains the original SQL structure while allowing you to redirect the workload to different databases or instances as needed.

    .PARAMETER SqlInstance
        Target SQL Server(s)

    .PARAMETER SqlCredential
        Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).

        Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.

        For MFA support, please use Connect-DbaInstance.

        The replay itself runs in sqlcmd, which logs in with the user name of the credential (-U) and gets the password through the environment variable SQLCMDPASSWORD, so that it never shows on the command line of sqlcmd. That is SQL Server Authentication.

    .PARAMETER Database
        Sets the initial database context for the replayed SQL statements. This determines which database sqlcmd connects to before executing the captured queries.
        Use this when you need to replay workloads in a specific database context, especially when the captured queries don't include explicit database references.

    .PARAMETER Event
        Filters which Extended Event types to replay from the input stream. Defaults to sql_batch_completed and rpc_completed events.
        Use this to replay only specific event types when you want to test particular workload patterns or exclude certain query types from the replay.

    .PARAMETER Raw
        Shows all sqlcmd output immediately without cleanup or formatting. By default, results are collected, cleaned, and filtered for readability.
        Use this when you need to see complete sqlcmd output including headers and formatting, or when troubleshooting query execution issues during replay.

    .PARAMETER InputObject
        Accepts Extended Event objects from Read-DbaXEFile or Read-DbaXESession containing captured SQL statements for replay.
        This is typically piped from Read-DbaXEFile when processing Extended Event files or from Read-DbaXESession for live session data.

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

    .OUTPUTS
        System.String

        Returns the output from sqlcmd execution. The exact content depends on the SQL queries being replayed.

        When -Raw is specified, all sqlcmd output is returned unmodified, including headers and formatting lines.

        When -Raw is not specified, output is filtered to remove sqlcmd formatting lines and column headers (lines containing only dashes), but query results and messages remain intact.

        If a replayed batch fails, the error message from sqlcmd is returned as a string. If no output is produced by the queries, nothing is returned.

        If sqlcmd cannot run the replay at all and exits with a code other than 0, for example because it cannot connect to the instance or open the database, the command writes a warning with the exit code and the error output of sqlcmd, or throws with -EnableException.

    .EXAMPLE
        PS C:\> Read-DbaXEFile -Path C:\temp\sample.xel | Invoke-DbaXEReplay -SqlInstance sql2017

        Replays the sql_batch_completed and rpc_completed events of sample.xel on sql2017, in the default database of the login.

    .EXAMPLE
        PS C:\> Read-DbaXEFile -Path C:\temp\sample.xel | Invoke-DbaXEReplay -SqlInstance sql2017 -Database planning -Event sql_batch_completed

        Sets the *initial* database to planning then runs only sql_batch_completed against sql2017.

    .EXAMPLE
        PS C:\> Read-DbaXEFile -Path C:\temp\sample.xel | Invoke-DbaXEReplay -SqlInstance sql2017, sql2016

        Replays the sql_batch_completed and rpc_completed events of sample.xel on sql2017 and on sql2016, in the default database of the login.


    #>
    [Cmdletbinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseOutputTypeCorrectly", "", Justification = "PSSA Rule Ignored by BOH")]
    param (
        [Parameter(Mandatory)]
        [DbaInstance[]]$SqlInstance,
        [PSCredential]$SqlCredential,
        [string[]]$Database,
        [string[]]$Event = @("sql_batch_completed", "rpc_completed"),
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]$InputObject,
        [switch]$Raw,
        [switch]$EnableException
    )

    begin {
        # Set before anything can stop, so that the cleanup in the end block never sees a variable of the caller.
        $filename = $null
        #Variable marked as unused by PSScriptAnalyzer
        #$querycolumns = 'statement', 'batch_text'

        if (-not (Get-Command sqlcmd -ErrorAction Ignore)) {
            Stop-Function -Message "sqlcmd is not installed. Please install the SQL Server Command Line Utilities."
            return
        }

        # The random part keeps two replays that start in the same minute from sharing one file.
        $timestamp = (Get-Date -Format yyyyMMddHHmm)
        $temp = ([System.IO.Path]::GetTempPath()).TrimEnd("\")
        $filename = "$temp\dbatools-replay-$timestamp-$(Get-Random).sql"

        # The file starts with the byte order mark of UTF-8. Without a mark every sqlcmd reads the file in an encoding
        # of its own: the ODBC sqlcmd in the ANSI code page, the Go sqlcmd as UTF-8. Add-Content writes the ANSI code page
        # in Windows PowerShell and UTF-8 without a mark in PowerShell 7, so one of the two would break the characters
        # outside ASCII. With the mark the ODBC sqlcmd 17 and 18 and the Go sqlcmd all read the file as UTF-8. The Go
        # sqlcmd does not know the -f option, so the code page cannot be passed instead.
        $fileEncoding = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllBytes($filename, (New-Object System.Text.UTF8Encoding($true)).GetPreamble())
    }
    process {
        if (Test-FunctionInterrupt) { return }
        # return, not continue: the process block is no loop, so a continue would leave the command and end the pipeline
        # of the caller at the first event that is not in -Event, before the end block replays anything.
        if ($InputObject.Name -notin $Event) {
            return
        }

        if ($InputObject.statement) {
            if ($InputObject.statement -notmatch "ALTER EVENT SESSION") {
                [System.IO.File]::AppendAllText($filename, "$($InputObject.statement)`r`nGO`r`n", $fileEncoding)
            }
        } else {
            if ($InputObject.batch_text -notmatch "ALTER EVENT SESSION") {
                [System.IO.File]::AppendAllText($filename, "$($InputObject.batch_text)`r`nGO`r`n", $fileEncoding)
            }
        }
    }
    end {
        # The replay file holds the captured statements, so it is removed in the finally, also when the replay stops
        # early or throws under -EnableException.
        $restoreSqlcmdPassword = $false
        try {
            if (Test-FunctionInterrupt) { return }

            # sqlcmd reads the password for -U from the environment variable SQLCMDPASSWORD. With -P on the command line
            # every user of the computer could read it from the process list while sqlcmd runs. The value the variable had
            # before is put back in the finally.
            $callerSqlcmdPassword = [Environment]::GetEnvironmentVariable("SQLCMDPASSWORD")
            $restoreSqlcmdPassword = $true
            if (Test-Bound -ParameterName SqlCredential) {
                [Environment]::SetEnvironmentVariable("SQLCMDPASSWORD", $SqlCredential.GetNetworkCredential().Password)
            }

            foreach ($instance in $SqlInstance) {
                try {
                    $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
                } catch {
                    Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
                }


                # The file is replayed once per database context. Without -Database, sqlcmd runs it once in the
                # default database of the login, which is what the command always did.
                $databaseContexts = $Database
                if (-not $databaseContexts) {
                    $databaseContexts = @($null)
                }

                foreach ($databaseContext in $databaseContexts) {
                    $sqlcmdArguments = @("-S", "$instance", "-i", $filename)
                    if ($databaseContext) {
                        $sqlcmdArguments += "-d", $databaseContext
                    }
                    if (Test-Bound -ParameterName SqlCredential) {
                        $sqlcmdArguments += "-U", $SqlCredential.UserName
                    }
                    # The ODBC sqlcmd 18 encrypts and validates the certificate of the server by default, so it refuses a
                    # server whose certificate the connection of dbatools trusts, for example by sql.connection.trustcert.
                    # -C makes sqlcmd trust it as well; the ODBC sqlcmd 17 and the Go sqlcmd know -C too.
                    if ($server.ConnectionContext.TrustServerCertificate) {
                        $sqlcmdArguments += "-C"
                    }

                    $replayTarget = "$instance"
                    if ($databaseContext) {
                        $replayTarget += " in database $databaseContext"
                    }

                    # Errors of the replayed batches come back as messages in the output and leave the exit code at 0.
                    # An exit code other than 0 means sqlcmd could not run the replay at all, for example because it could
                    # not log in. The ODBC sqlcmd writes the reason to its error output only.
                    if ($Raw) {
                        Write-Message -Message "Invoking XEReplay against $instance running on $($server.name) with raw output" -Level Verbose
                        & sqlcmd @sqlcmdArguments
                        if ($LASTEXITCODE -ne 0) {
                            Stop-Function -Message "sqlcmd could not replay the file on $replayTarget, exit code $LASTEXITCODE." -Target $instance -Continue
                        }
                        continue
                    }

                    Write-Message -Message "Invoking XEReplay against $instance running on $($server.name)" -Level Verbose
                    # The error output is collected with the output, in a scope of its own: Windows PowerShell turns every
                    # line a native command writes to its error output into an error, and with an ErrorActionPreference
                    # of Stop in the caller the first such line would end the command.
                    $output = & {
                        $ErrorActionPreference = "Continue"
                        & sqlcmd @sqlcmdArguments 2>&1
                    }
                    $exitCode = $LASTEXITCODE
                    $sqlcmdErrors = @()

                    # sqlcmd underlines every column header with dashes as wide as the column, and several columns
                    # give one line of dash runs with spaces in between, so the whole line is tested.
                    foreach ($line in $output) {
                        if ($line -is [System.Management.Automation.ErrorRecord]) {
                            $sqlcmdErrors += "$line".Trim()
                            continue
                        }
                        $newline = $line.Trim()
                        if ($newline -and $newline -notmatch "^[-\s]+$") {
                            "$newline"
                        }
                    }

                    if ($exitCode -ne 0) {
                        Stop-Function -Message "sqlcmd could not replay the file on $replayTarget, exit code $exitCode. $($sqlcmdErrors -join " ")" -Target $instance -Continue
                    }
                }
            }
        } finally {
            if ($restoreSqlcmdPassword) {
                [Environment]::SetEnvironmentVariable("SQLCMDPASSWORD", $callerSqlcmdPassword)
            }
            if ($filename) {
                Remove-Item -Path $filename -ErrorAction Ignore
            }
        }
    }
}