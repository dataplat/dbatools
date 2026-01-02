function Get-DbaWindowsLog {
    <#
    .SYNOPSIS
        Retrieves and parses SQL Server error log entries from the file system for analysis and troubleshooting

    .DESCRIPTION
        Parses SQL Server error log files directly from the file system to extract structured error information including timestamps, SPIDs, error numbers, severity levels, and messages. Locates error log files by querying Windows Application Event Log for SQL Server startup events (Event ID 17111), then reads and parses the raw log files to provide searchable, filterable results. This is essential for troubleshooting SQL Server issues, compliance reporting, and proactive monitoring since it gives you programmatic access to detailed error information that would otherwise require manual log file review.

    .PARAMETER SqlInstance
        The instance(s) to retrieve the event logs from

    .PARAMETER Start
        Filters log entries to include only those occurring after this timestamp. Defaults to January 1, 1970.
        Use this to focus on recent issues or events within a specific timeframe when troubleshooting SQL Server problems.

    .PARAMETER End
        Filters log entries to include only those occurring before this timestamp. Defaults to the current date and time.
        Combine with Start parameter to create specific time windows for analyzing SQL Server events during known problem periods.

    .PARAMETER Credential
        Credential to be used to connect to the Server. Note this is a Windows credential, as this command requires we communicate with the computer and not with the SQL instance.

    .PARAMETER MaxThreads
        Controls the maximum number of parallel threads used on the local computer for processing multiple SQL instances. Defaults to unlimited.
        Set a specific limit when processing many instances simultaneously to prevent overwhelming the local system with too many concurrent operations.

    .PARAMETER MaxRemoteThreads
        Sets the maximum number of parallel threads executed on each target SQL Server for processing error log files. Defaults to 2.
        Keep this low to avoid excessive CPU load on production servers, as log file parsing is CPU-intensive. Set to 0 or below to remove the limit entirely.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Logging, OS
        Author: Drew Furgiuele | Friedrich Weinmann (@FredWeinmann)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaWindowsLog

    .OUTPUTS
        PSCustomObject

        Returns one object per parsed error log entry found in SQL Server error log files within the specified time range. Each object contains details about a single error log record including timestamp, SPID, severity, error number, and the log message.

        Properties:
        - InstanceName: The SQL Server instance name where the log entry originated (format: ComputerName\InstanceName or ComputerName for default instance)
        - Timestamp: The date and time when the error log entry was recorded (DateTime)
        - Spid: The SQL Server process ID (SPID) associated with the log entry; typically a string value like "s", "sa", "sr" for system processes (string)
        - Severity: The severity level of the error (0-25 numeric scale; 10+ indicates user errors, lower values indicate informational messages, string representation)
        - ErrorNumber: The SQL Server error number; 0 for informational messages, >0 for actual errors (int)
        - State: The error state number providing additional diagnostic context for the error (int)
        - Message: The full text of the error log message (string)

        Note: The function parses raw SQL Server error log files using regular expressions. Only entries matching the error log format pattern are returned. Non-matching log entries are silently skipped. Results are always output as log entries are parsed during the remote execution, not held in memory.

    .EXAMPLE
        PS C:\> $ErrorLogs = Get-DbaWindowsLog -SqlInstance sql01\sharepoint
        PS C:\> $ErrorLogs | Where-Object ErrorNumber -eq 18456

        Returns all lines in the errorlogs that have event number 18456 in them

    #>
    #This exists to ignore the Script Analyzer rule for Start-Runspace
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSUseShouldProcessForStateChangingFunctions", "")]
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline)]
        [DbaInstanceParameter[]]
        $SqlInstance = $env:COMPUTERNAME,

        [DateTime]
        $Start = "1/1/1970 00:00:00",

        [DateTime]
        $End = (Get-Date),


        [System.Management.Automation.PSCredential]
        $Credential,

        [int]
        $MaxThreads = 0,

        [int]
        $MaxRemoteThreads = 2,

        [switch]$EnableException
    )

    begin {
        Write-Message -Level Debug -Message "Bound parameters: $($PSBoundParameters.Keys -join ", ")"

        #region Helper Functions
        function Start-Runspace {
            $Powershell = [PowerShell]::Create().AddScript($scriptBlock_ParallelRemoting).AddParameter("SqlInstance", $instance).AddParameter("Start", $Start).AddParameter("End", $End).AddParameter("Credential", $Credential).AddParameter("MaxRemoteThreads", $MaxRemoteThreads).AddParameter("ScriptBlock", $scriptBlock_RemoteExecution)
            $Powershell.RunspacePool = $RunspacePool
            Write-Message -Level Verbose -Message "Launching remote runspace against <c='green'>$instance</c>" -Target $instance
            $null = $RunspaceCollection.Add((New-Object -TypeName PSObject -Property @{ Runspace = $PowerShell.BeginInvoke(); PowerShell = $PowerShell; Instance = $instance.FullSmoName }))
        }

        function Receive-Runspace {
            [Parameter()]
            param (
                [switch]
                $Wait
            )

            do {
                foreach ($Run in $RunspaceCollection.ToArray()) {
                    if ($Run.Runspace.IsCompleted) {
                        Write-Message -Level Verbose -Message "Receiving results from <c='green'>$($Run.Instance)</c>" -Target $Run.Instance
                        $Run.PowerShell.EndInvoke($Run.Runspace)
                        $Run.PowerShell.Dispose()
                        $RunspaceCollection.Remove($Run)
                    }
                }

                if ($Wait -and ($RunspaceCollection.Count -gt 0)) { Start-Sleep -Milliseconds 250 }
            }
            while ($Wait -and ($RunspaceCollection.Count -gt 0))
        }
        #endregion Helper Functions

        #region Scriptblocks
        $scriptBlock_RemoteExecution = {
            param (
                [System.DateTime]
                $Start,

                [System.DateTime]
                $End,

                [string]
                $InstanceName,

                [int]
                $Throttle
            )

            #region Helper function
            function Convert-ErrorRecord {
                param (
                    $Line
                )

                if (Get-Variable -Name codesAndStuff -Scope 1) {
                    $line2 = (Get-Variable -Name codesAndStuff -Scope 1).Value
                    Remove-Variable -Name codesAndStuff -Scope 1

                    $groups = [regex]::Matches($line2, '^([\d- :]+.\d\d) (\w+)[ ]+Error: (\d+), Severity: (\d+), State: (\d+)').Groups
                    $groups2 = [regex]::Matches($line, '^[\d- :]+.\d\d \w+[ ]+(.*)$').Groups

                    New-Object PSObject -Property @{
                        Timestamp   = [DateTime]::ParseExact($groups[1].Value, "yyyy-MM-dd HH:mm:ss.ff", $null)
                        Spid        = $groups[2].Value
                        Message     = $groups2[1].Value
                        ErrorNumber = [int]($groups[3].Value)
                        Severity    = [int]($groups[4].Value)
                        State       = [int]($groups[5].Value)
                    }
                }

                if ($Line -match '^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d\d[\w ]+((\w+): (\d+)[,\.]\s?){3}') {
                    Set-Variable -Name codesAndStuff -Value $Line -Scope 1
                }
            }
            #endregion Helper function

            #region Script that processes an individual file
            $scriptBlock = {
                param (
                    [System.IO.FileInfo]
                    $File
                )

                try {
                    $stream = New-Object System.IO.FileStream($File.FullName, "Open", "Read", "ReadWrite, Delete")
                    $reader = New-Object System.IO.StreamReader($stream)

                    while (-not $reader.EndOfStream) {
                        Convert-ErrorRecord -Line $reader.ReadLine()
                    }
                } catch {
                    # here to avoid an empty catch
                    $null = 1
                }
            }
            #endregion Script that processes an individual file

            #region Gather list of files to process
            $eventSource = "MSSQLSERVER"
            if ($InstanceName -notmatch "^DEFAULT$|^MSSQLSERVER$") {
                $eventSource = 'MSSQL$' + $InstanceName
            }

            $event = Get-WinEvent -FilterHashtable @{
                LogName      = "Application"
                ID           = 17111
                ProviderName = $eventSource
            } -MaxEvents 1 -ErrorAction SilentlyContinue

            if (-not $event) { return }

            $path = $event.Properties[0].Value
            $errorLogPath = Split-Path -Path $path
            $errorLogFileName = Split-Path -Path $path -Leaf
            $errorLogFiles = Get-ChildItem -Path $errorLogPath | Where-Object { ($_.Name -like "$errorLogFileName*") -and ($_.LastWriteTime -gt $Start) -and ($_.CreationTime -lt $End) }
            #endregion Gather list of files to process

            #region Prepare Runspaces
            [Collections.Arraylist]$RunspaceCollection = @()

            $InitialSessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $Command = Get-Item function:Convert-ErrorRecord
            $InitialSessionState.Commands.Add((New-Object System.Management.Automation.Runspaces.SessionStateFunctionEntry($command.Name, $command.Definition)))

            $RunspacePool = [RunspaceFactory]::CreateRunspacePool($InitialSessionState)
            $null = $RunspacePool.SetMinRunspaces(1)
            if ($Throttle -gt 0) { $null = $RunspacePool.SetMaxRunspaces($Throttle) }
            $RunspacePool.Open()
            #endregion Prepare Runspaces

            #region Process Error files
            $countDone = 0
            $countStarted = 0
            $countTotal = ($errorLogFiles | Measure-Object).Count

            while ($countDone -lt $countTotal) {
                while (($RunspacePool.GetAvailableRunspaces() -gt 0) -and ($countStarted -lt $countTotal)) {
                    $Powershell = [PowerShell]::Create().AddScript($scriptBlock).AddParameter("File", $errorLogFiles[$countStarted])
                    $Powershell.RunspacePool = $RunspacePool
                    $null = $RunspaceCollection.Add((New-Object -TypeName PSObject -Property @{ Runspace = $PowerShell.BeginInvoke(); PowerShell = $PowerShell }))
                    $countStarted++
                }

                foreach ($Run in $RunspaceCollection.ToArray()) {
                    if ($Run.Runspace.IsCompleted) {
                        $Run.PowerShell.EndInvoke($Run.Runspace) | Where-Object { ($_.Timestamp -gt $Start) -and ($_.Timestamp -lt $End) }
                        $Run.PowerShell.Dispose()
                        $RunspaceCollection.Remove($Run)
                        $countDone++
                    }
                }

                Start-Sleep -Milliseconds 250
            }
            $RunspacePool.Close()
            $RunspacePool.Dispose()
            #endregion Process Error files
        }

        $scriptBlock_ParallelRemoting = {
            param (
                [DbaInstanceParameter]
                $SqlInstance,

                [DateTime]
                $Start,

                [DateTime]
                $End,

                [PSCredential]
                $Credential,

                [int]
                $MaxRemoteThreads,

                [System.Management.Automation.ScriptBlock]
                $ScriptBlock
            )

            $params = @{
                ArgumentList = $Start, $End, $SqlInstance.InstanceName, $MaxRemoteThreads
                ScriptBlock  = $ScriptBlock
            }
            if (-not $SqlInstance.IsLocalhost) { $params["ComputerName"] = $SqlInstance.ComputerName }
            if ($Credential) { $params["Credential"] = $Credential }

            Invoke-Command @params | Select-Object @{ n = "InstanceName"; e = { $SqlInstance.FullSmoName } }, Timestamp, Spid, Severity, ErrorNumber, State, Message
        }
        #endregion Scriptblocks

        #region Setup Runspace
        [Collections.Arraylist]$RunspaceCollection = @()
        $InitialSessionState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
        $defaultrunspace = [System.Management.Automation.Runspaces.Runspace]::DefaultRunspace
        $RunspacePool = [RunspaceFactory]::CreateRunspacePool($InitialSessionState)
        $RunspacePool.SetMinRunspaces(1) | Out-Null
        if ($MaxThreads -gt 0) { $null = $RunspacePool.SetMaxRunspaces($MaxThreads) }
        $RunspacePool.Open()

        $countStarted = 0
        #Variable marked as unused by PSScriptAnalyzer
        #$countReceived = 0
        #endregion Setup Runspace
    }

    process {
        foreach ($instance in $SqlInstance) {
            Write-Message -Level VeryVerbose -Message "Processing <c='green'>$instance</c>" -Target $instance
            Start-Runspace
            Receive-Runspace
        }
    }

    end {
        Receive-Runspace -Wait
        $RunspacePool.Close()
        $RunspacePool.Dispose()
        [System.Management.Automation.Runspaces.Runspace]::DefaultRunspace = $defaultrunspace
    }
}