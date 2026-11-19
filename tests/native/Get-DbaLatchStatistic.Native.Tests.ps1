#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
# NativeChecklist: whatif-confirm N/A -- the pinned command declares [CmdletBinding()] without SupportsShouldProcess and changes nothing, so it has no -WhatIf or -Confirm.
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaLatchStatistic",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe "Native Get-DbaLatchStatistic" -Tag IntegrationTests {
    BeforeAll {
        $latchServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $latchTag = [guid]::NewGuid().ToString("N").Substring(0, 10)
        $latchMissing = "nf" + [guid]::NewGuid().ToString("N").Substring(0, 12)
        $latchNames = "ComputerName,InstanceName,SqlInstance,WaitType,WaitSeconds,WaitCount,Percentage,AverageWaitSeconds,URL"
        $latchLink = "https://www.sqlskills.com/help/latches/"

        # Independent read on the test's own connection: the latch classes the view lists, and the wait time of the classes
        # the pinned query weighs (every class but BUFFER).
        function Get-NativeLatchClass {
            param($Server)
            @($Server.Query("SELECT [latch_class] FROM sys.dm_os_latch_stats;") | ForEach-Object { $PSItem.latch_class })
        }
        function Get-NativeLatchWait {
            param($Server)
            [long](@($Server.Query("SELECT ISNULL(SUM([wait_time_ms]), 0) AS [total] FROM sys.dm_os_latch_stats WHERE [latch_class] NOT IN (N'BUFFER');"))[0].total)
        }

        # Each row as the pinned query computes it: the classes of the view but BUFFER, a link built from the class, the
        # average from the unrounded seconds (so within rounding of WaitSeconds / WaitCount), and no average without a wait.
        function Assert-NativeLatchRow {
            param($Row, $Server, [string[]]$Classes)
            ($Row.PSObject.Properties.Name -join ",") | Should -BeExactly $latchNames
            $Row.PSStandardMembers.DefaultDisplayPropertySet | Should -BeNullOrEmpty
            $Row.ComputerName | Should -BeExactly $Server.ComputerName
            $Row.InstanceName | Should -BeExactly $Server.ServiceName
            $Row.SqlInstance | Should -BeExactly $Server.DomainInstanceName
            $Row.WaitType | Should -BeOfType [string]
            $Row.WaitType | Should -BeIn $Classes
            $Row.WaitType | Should -Not -BeExactly "BUFFER"
            $Row.URL | Should -BeOfType [string]
            $Row.URL | Should -BeExactly ($latchLink + $Row.WaitType)
            $Row.WaitSeconds | Should -BeOfType [decimal]
            $Row.WaitCount | Should -BeOfType [long]
            $Row.Percentage | Should -BeOfType [decimal]
            $Row.Percentage | Should -BeGreaterOrEqual 0
            $Row.Percentage | Should -BeLessOrEqual 100
            if ($Row.WaitCount -gt 0) {
                $Row.AverageWaitSeconds | Should -BeOfType [decimal]
                [math]::Abs($Row.AverageWaitSeconds - ($Row.WaitSeconds / $Row.WaitCount)) | Should -BeLessOrEqual ([decimal]0.006)
            } else {
                $Row.AverageWaitSeconds | Should -BeOfType [System.DBNull]
            }
        }
    }

    Context "Results" {
        It "returns each latch class in the pinned shape, with its sqlskills link" {
            $results = @(Get-DbaLatchStatistic -SqlInstance $TestConfig.InstanceSingle -Threshold 100 -ErrorVariable latchErrors)
            $classes = Get-NativeLatchClass $latchServer
            $latchErrors | Should -BeNullOrEmpty
            $results | Should -Not -BeNullOrEmpty
            foreach ($result in $results) {
                Assert-NativeLatchRow -Row $result -Server $latchServer -Classes $classes
            }
            @($results.WaitType | Select-Object -Unique).Count | Should -Be $results.Count
        }

        It "keeps only the latch classes before the -Threshold share of the wait time" {
            # The pinned HAVING keeps a class while the classes with more wait time before it make up less than the threshold.
            $half = @(Get-DbaLatchStatistic -SqlInstance $TestConfig.InstanceSingle -Threshold 50 -ErrorVariable halfErrors)
            $halfErrors | Should -BeNullOrEmpty
            $half | Should -Not -BeNullOrEmpty
            $sorted = @($half | Sort-Object -Property Percentage -Descending)
            $before = [decimal]0
            foreach ($row in $sorted) {
                $before | Should -BeLessThan ([decimal]50 + [decimal]0.01 * $sorted.Count)
                $before += $row.Percentage
            }
        }

        It "returns no latch class for -Threshold 0, as no class has less than nothing before it" {
            $none = @(Get-DbaLatchStatistic -SqlInstance $TestConfig.InstanceSingle -Threshold 0 -ErrorVariable noneErrors)
            $noneErrors | Should -BeNullOrEmpty
            $none.Count | Should -Be 0
        }
    }

    Context "Instances" {
        It "returns the latch classes of each piped instance and goes on past one that fails" -Tag "NativeChecklist:pipeline-multiple", "NativeChecklist:multi-instance-failure", "NativeChecklist:switch-false" {
            $warnings = @()
            $results = @(@($TestConfig.InstanceSingle, $latchMissing, $TestConfig.InstanceSingle) | Get-DbaLatchStatistic -Threshold 100 -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings)
            $groups = @($results | Group-Object -Property WaitType | Where-Object Count -eq 2)
            $groups | Should -Not -BeNullOrEmpty
            @($results | Where-Object SqlInstance -ne $latchServer.DomainInstanceName) | Should -BeNullOrEmpty
            $warnings.Count | Should -Be 1
            "$($warnings[0])" | Should -Match ([regex]::Escape("[Get-DbaLatchStatistic] Failure | Error connecting to [$latchMissing]: "))
        }

        It "reads several named instances" {
            $first = @(Get-DbaLatchStatistic -SqlInstance $TestConfig.InstanceSingle -Threshold 100)
            $results = @(Get-DbaLatchStatistic -SqlInstance $TestConfig.InstanceSingle, $TestConfig.InstanceSingle -Threshold 100)
            $first | Should -Not -BeNullOrEmpty
            # The class with the most wait time has nothing before it, so every threshold above 0 keeps it.
            $top = @($first | Sort-Object -Property WaitSeconds -Descending)[0].WaitType
            @($results | Where-Object WaitType -eq $top).Count | Should -Be 2
        }

        It "throws the connection failure under -EnableException" -Tag "NativeChecklist:enable-exception" {
            $caught = $null
            try {
                $null = Get-DbaLatchStatistic -SqlInstance $latchMissing -EnableException -WarningAction SilentlyContinue
            } catch {
                $caught = $PSItem
            }
            $caught | Should -Not -BeNullOrEmpty
            $caught.CategoryInfo.Category | Should -Be "ConnectionError"
        }
    }

    Context "A login without server state permission" {
        BeforeAll {
            # The pin runs $server.Query outside any try. A SQL login with no server permission connects, and the read of
            # sys.dm_os_latch_stats then faults: it needs VIEW SERVER STATE (VIEW SERVER PERFORMANCE STATE from SQL Server
            # 2022 on), which a new login does not have.
            # https://learn.microsoft.com/sql/relational-databases/system-dynamic-management-views/sys-dm-os-latch-stats-transact-sql
            $lowName = "dbatoolsci_latch_${latchTag}_low"
            $lowPassword = "Latch-" + [guid]::NewGuid().ToString("N")
            $lowCred = New-Object System.Management.Automation.PSCredential -ArgumentList $lowName, (ConvertTo-SecureString -String $lowPassword -AsPlainText -Force)
            $null = $latchServer.Query("CREATE LOGIN [$lowName] WITH PASSWORD = N'$lowPassword', CHECK_POLICY = OFF, DEFAULT_DATABASE = [master];")

            function New-NativeLowServer {
                Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -SqlCredential $lowCred -EnableException
            }

            # Independent read: the record the module's Server.Query script method gives this login for a read of the same
            # view, called with one argument as the pin calls it.
            $lowReference = $null
            try {
                $null = (New-NativeLowServer).Query("SELECT [latch_class], [wait_time_ms] FROM sys.dm_os_latch_stats WHERE [latch_class] NOT IN (N'BUFFER');")
            } catch {
                $lowReference = $PSItem
            }

            # The pin's record for this fault: the method call fault of the Server.Query script method.
            function Assert-NativeQueryFault {
                param($Record)
                $lowReference | Should -Not -BeNullOrEmpty
                ($Record.FullyQualifiedErrorId -split ",")[0] | Should -BeExactly "ScriptMethodRuntimeException"
                ($lowReference.FullyQualifiedErrorId -split ",")[0] | Should -BeExactly "ScriptMethodRuntimeException"
                $Record.Exception | Should -BeOfType [System.Management.Automation.MethodInvocationException]
                $Record.Exception.GetType().FullName | Should -BeExactly $lowReference.Exception.GetType().FullName
                $Record.Exception.Message | Should -BeExactly $lowReference.Exception.Message
                $Record.Exception.Message | Should -BeLike 'Exception calling "Query" with "1" argument(s): *permission*'
                $Record.Exception.InnerException.GetType().FullName | Should -BeExactly $lowReference.Exception.InnerException.GetType().FullName
                $Record.Exception.InnerException.Message | Should -BeExactly $lowReference.Exception.InnerException.Message
                "$($Record.CategoryInfo.Category)" | Should -BeExactly "$($lowReference.CategoryInfo.Category)"
                "$($Record.TargetObject)" | Should -BeExactly ""
            }

            # A Pester It runs its body inside a try, so a call outside any try needs a runspace of its own.
            function Invoke-NativeLatchOutsideTry {
                param([hashtable]$Arguments)
                $outsideState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
                $outsideType = (Get-Command Get-DbaLatchStatistic -CommandType Cmdlet).ImplementingType
                $outsideEntry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList "Get-DbaLatchStatistic", $outsideType, $null
                $outsideState.Commands.Add($outsideEntry)
                $outsideRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($outsideState)
                $outsideShell = [System.Management.Automation.PowerShell]::Create()
                $outsideOutput = New-Object "System.Management.Automation.PSDataCollection[psobject]"
                $outsideStop = $null
                try {
                    $outsideRunspace.Open()
                    $outsideShell.Runspace = $outsideRunspace
                    $null = $outsideShell.AddScript('param($Arguments) Get-DbaLatchStatistic @Arguments; "next statement"').AddArgument($Arguments)
                    try {
                        $null = $outsideShell.Invoke($null, $outsideOutput)
                    } catch {
                        $outsideStop = $PSItem.Exception.InnerException
                    }
                    [pscustomobject]@{
                        Output   = @($outsideOutput)
                        Errors   = @($outsideShell.Streams.Error)
                        Warnings = @($outsideShell.Streams.Warning)
                        Stop     = $outsideStop
                    }
                } finally {
                    $outsideShell.Dispose()
                    $outsideRunspace.Dispose()
                }
            }
        }

        AfterAll {
            foreach ($row in @($latchServer.Query("SELECT session_id FROM sys.dm_exec_sessions WHERE login_name = N'$lowName';"))) {
                $null = $latchServer.Query("KILL $($row.session_id);")
            }
            $null = $latchServer.Query("IF SUSER_ID(N'$lowName') IS NOT NULL DROP LOGIN [$lowName];")
        }

        It "writes each instance's query fault and goes on, outside any try" {
            $outside = Invoke-NativeLatchOutsideTry @{ SqlInstance = @((New-NativeLowServer), (New-NativeLowServer)) }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Warnings.Count | Should -Be 0
            $outside.Errors.Count | Should -Be 2
            foreach ($record in $outside.Errors) {
                Assert-NativeQueryFault -Record $record
            }
            ($outside.Output -join ",") | Should -BeExactly "next statement"
        }

        It "goes on to the next instance's latch classes after a query fault" {
            $outside = Invoke-NativeLatchOutsideTry @{ SqlInstance = @((New-NativeLowServer), $latchServer); Threshold = 100 }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            Assert-NativeQueryFault -Record $outside.Errors[0]
            $rows = @($outside.Output | Where-Object { $PSItem -isnot [string] })
            $rows | Should -Not -BeNullOrEmpty
            @($rows | Where-Object SqlInstance -ne $latchServer.DomainInstanceName) | Should -BeNullOrEmpty
            @($outside.Output)[-1] | Should -BeExactly "next statement"
        }

        It "stops at the first query fault under -EnableException" -Tag "NativeChecklist:enable-exception" {
            $outside = Invoke-NativeLatchOutsideTry @{ SqlInstance = @((New-NativeLowServer), (New-NativeLowServer)); EnableException = $true }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            Assert-NativeQueryFault -Record $outside.Errors[0]
            ($outside.Output -join ",") | Should -BeExactly "next statement"
        }

        It "lets a caller's try catch the first query fault" {
            $first = New-NativeLowServer
            $second = New-NativeLowServer
            $callerOutput = @(try { Get-DbaLatchStatistic -SqlInstance $first, $second; "after" } catch { $_ })
            $callerOutput.Count | Should -Be 1
            $callerOutput[0] | Should -BeOfType [System.Management.Automation.ErrorRecord]
            Assert-NativeQueryFault -Record $callerOutput[0]
        }

        It "stops at the first query fault under -ErrorAction Stop, outside a try" {
            $outside = Invoke-NativeLatchOutsideTry @{ SqlInstance = @((New-NativeLowServer), (New-NativeLowServer)); ErrorAction = "Stop" }
            $outside.Stop | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
            Assert-NativeQueryFault -Record $outside.Stop.ErrorRecord
            $outside.Output.Count | Should -Be 0
        }
    }

    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
            # Every leg shares this instance at once, so this context creates nothing: it reads the latch classes as they are,
            # on the test's own SQL-login connection.
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
        }

        It "works with -SqlCredential" {
            # Other lanes may clear this shared instance's latch statistics, so a row is required only when the view held
            # wait time just before the call.
            $loginWait = Get-NativeLatchWait $loginServer
            $result = @(Get-DbaLatchStatistic -SqlInstance $loginInstance -SqlCredential $loginCred -Threshold 100 -EnableException -ErrorVariable loginErrors)
            $loginClasses = Get-NativeLatchClass $loginServer
            $loginErrors | Should -BeNullOrEmpty
            if ($loginWait -gt 0) {
                $result | Should -Not -BeNullOrEmpty
            }
            foreach ($row in $result) {
                Assert-NativeLatchRow -Row $row -Server $loginServer -Classes $loginClasses
            }
        }

        It "fails cleanly without the credential: a warning and no output" {
            $warnings = @()
            $result = Get-DbaLatchStatistic -SqlInstance $loginInstance -WarningVariable warnings -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            $warnings | Should -Not -BeNullOrEmpty
        }

        It "throws without the credential under -EnableException, as the pinned Stop-Function does" {
            { Get-DbaLatchStatistic -SqlInstance $loginInstance -EnableException -WarningAction SilentlyContinue } | Should -Throw
        }
    }

    Context "Azure SQL Database" -Tag NativeChecklist:azure-sqldb {
        BeforeAll {
            # sys.dm_os_latch_stats applies to Azure SQL Database (VIEW DATABASE STATE, or the server admin on Basic, S0 and S1).
            # https://learn.microsoft.com/sql/relational-databases/system-dynamic-management-views/sys-dm-os-latch-stats-transact-sql
            $azure = $null
            for ($attempt = 0; $attempt -le 6; $attempt++) {
                try {
                    $azure = Connect-DbaInstance -SqlInstance $TestConfig.AzureSqlDbServer -Database $TestConfig.AzureSqlDbName -SqlCredential $TestConfig.AzureSqlDbCred -EnableException
                    break
                } catch {
                    $azureError = $PSItem.Exception
                    $isResuming = $false
                    while ($azureError) {
                        if ($azureError.Number -in 40613, -2 -or $azureError -is [System.TimeoutException]) { $isResuming = $true }
                        $azureError = $azureError.InnerException
                    }
                    if (-not $isResuming -or $attempt -eq 6) { throw }
                    Start-Sleep -Seconds 10
                }
            }
        }

        AfterAll {
            if ($azure) { $azure.ConnectionContext.Disconnect() }
        }

        It "returns the latch classes of the Azure SQL Database in the pinned shape" {
            $azure.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
            # The view only grows between these reads unless something clears it, so wait time before the call means a row.
            $azureWait = Get-NativeLatchWait $azure
            $azureWarnings = @()
            $rows = @(Get-DbaLatchStatistic -SqlInstance $azure -Threshold 100 -WarningAction SilentlyContinue -WarningVariable azureWarnings -ErrorVariable azureErrors -ErrorAction SilentlyContinue)
            $azureClasses = Get-NativeLatchClass $azure
            $azureErrors | Should -BeNullOrEmpty
            $azureWarnings | Should -BeNullOrEmpty
            $azureClasses | Should -Not -BeNullOrEmpty
            if ($azureWait -gt 0) {
                $rows | Should -Not -BeNullOrEmpty
            }
            foreach ($row in $rows) {
                Assert-NativeLatchRow -Row $row -Server $azure -Classes $azureClasses
            }
        }

        It "reads Azure SQL Database under -EnableException and goes on to the next instance" {
            $azure.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
            $rows = @(Get-DbaLatchStatistic -SqlInstance $azure, $latchServer -Threshold 100 -EnableException)
            @($rows | Where-Object SqlInstance -eq $latchServer.DomainInstanceName) | Should -Not -BeNullOrEmpty
        }
    }
}
