function Get-DbaWindowsLog {
    <#
    .SYNOPSIS
        Gets Windows Application events associated with an instance

    .DESCRIPTION
        Gets Windows Application events associated with an instance

    .PARAMETER SqlInstance
        The instance(s) to retrieve the event logs from

    .PARAMETER Start
        Default: 1970
        Retrieve all events starting from this timestamp.

    .PARAMETER End
        Default: Now
        Retrieve all events that happened before this timestamp

    .PARAMETER Credential
        Credential to be used to connect to the Server. Note this is a Windows credential, as this command requires we communicate with the computer and not with the SQL instance.

    .PARAMETER MaxThreads
        Default: Unlimited
        The maximum number of parallel threads used on the local computer.
        Given that those will mostly be waiting for the remote system, there is usually no need to limit this.

    .PARAMETER MaxRemoteThreads
        Default: 2
        The maximum number of parallel threads that are executed on the target sql server.
        These processes will cause considerable CPU load, so a low limit is advisable in most scenarios.
        Any value lower than 1 disables the limit

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Logging
        Author: Drew Furgiuele | Friedrich Weinmann (@FredWeinmann)

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaWindowsLog

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