#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaDbccProcCache",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- the pinned command has no SupportsShouldProcess, WhatIf or Confirm parameters; it only reads DBCC PROCCACHE.

# Expected values below are as the pin measured on both editions: evidence/pin-proccache-20261103.txt.
# A failed connect writes one warning line naming the server, where the pin writes two (bad-instance-first, login-no-credential): an accepted difference,
# harness-edits.md, "Script-scope preferences and the one-line connect warning", points 5 to 7.

Describe "Native Get-DbaDbccProcCache" -Tag IntegrationTests {
    BeforeAll {
        $instance = $TestConfig.InstanceSingle
        $missingInstance = "nativeproccache$(Get-Random)"
        # The fixture's connection is never given to the command.
        $server = Connect-DbaInstance -SqlInstance $instance -NonPooledConnection -EnableException
    }

    AfterAll {
        $server.ConnectionContext.Disconnect()
    }

    Context "Output" {
        It "returns one plain object per row, with the pinned properties in their order and the row's types" {
            $engine = $server.ConnectionContext.ExecuteWithResults("DBCC PROCCACHE WITH NO_INFOMSGS").Tables[0]
            $result = @(Get-DbaDbccProcCache -SqlInstance $instance -EnableException)

            $result.Count | Should -Be $engine.Rows.Count
            $result[0].PSObject.TypeNames[0] | Should -BeExactly "System.Management.Automation.PSCustomObject"
            $result[0].PSObject.Properties.Name | Should -BeExactly @("ComputerName", "InstanceName", "SqlInstance", "Count", "Used", "Active", "CacheSize", "CacheUsed", "CacheActive")
            $result[0].ComputerName | Should -BeExactly $server.ComputerName
            $result[0].InstanceName | Should -BeExactly $server.ServiceName
            $result[0].SqlInstance | Should -BeExactly $server.DomainInstanceName

            # The plan cache moves between two reads, so the values are not compared with the independent read.
            $properties = "Count", "Used", "Active", "CacheSize", "CacheUsed", "CacheActive"
            for ($ordinal = 0; $ordinal -lt 6; $ordinal++) {
                $result[0].($properties[$ordinal]).GetType().FullName | Should -BeExactly $engine.Rows[0][$ordinal].GetType().FullName
            }
        }

        # Microsoft Learn: the first three columns count pages and the last three count entries, and an entry holds at least one page.
        It "reports the pages before the entries they belong to" {
            $result = Get-DbaDbccProcCache -SqlInstance $instance -EnableException
            $result.Count | Should -BeGreaterOrEqual $result.CacheSize
            $result.Used | Should -BeGreaterOrEqual $result.CacheUsed
        }

        It "reads through a server object" {
            $own = Connect-DbaInstance -SqlInstance $instance -EnableException
            $result = @($own | Get-DbaDbccProcCache -EnableException)
            $result.Count | Should -Be 1
            $result[0].SqlInstance | Should -BeExactly $own.DomainInstanceName
        }

        It "writes the pinned verbose line" {
            $verbose = @(Get-DbaDbccProcCache -SqlInstance $instance -Verbose -EnableException 4>&1 | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] } | ForEach-Object { $PSItem.Message })
            @($verbose | Where-Object { $PSItem -like "*Get-DbaDbccProcCache*Query to run: DBCC PROCCACHE WITH NO_INFOMSGS" }).Count | Should -Be 1
        }
    }

    Context "Instances" {
        It "reads each piped instance" -Tag "NativeChecklist:pipeline-multiple" {
            $results = @($instance, $instance | Get-DbaDbccProcCache -EnableException)
            $results.Count | Should -Be 2
            $results[0].SqlInstance | Should -BeExactly $server.DomainInstanceName
            $results[1].SqlInstance | Should -BeExactly $server.DomainInstanceName
        }

        It "reads each instance of an array" {
            @(Get-DbaDbccProcCache -SqlInstance $instance, $instance -EnableException).Count | Should -Be 2
        }
    }

    Context "An instance that cannot be reached" {
        It "warns and goes on to the next instance" -Tag "NativeChecklist:multi-instance-failure" {
            $warnings = $null
            $results = @(Get-DbaDbccProcCache -SqlInstance $missingInstance, $instance -WarningVariable warnings -WarningAction SilentlyContinue)
            $results.Count | Should -Be 1
            @($warnings).Count | Should -Be 1
            "$($warnings[0])" | Should -Match "\[Get-DbaDbccProcCache\] Failure \| Error connecting to \[$missingInstance\]: "
        }

        It "warns and goes on under -EnableException:`$false" -Tag "NativeChecklist:switch-false" {
            $warnings = $null
            $results = @(Get-DbaDbccProcCache -SqlInstance $missingInstance, $instance -EnableException:$false -WarningVariable warnings -WarningAction SilentlyContinue)
            $results.Count | Should -Be 1
            @($warnings).Count | Should -Be 1
        }

        It "throws the connection failure under -EnableException, before the next instance" -Tag "NativeChecklist:enable-exception" {
            $caught = $null
            $collected = $null
            $warnings = $null
            try {
                $null = Get-DbaDbccProcCache -SqlInstance $missingInstance, $instance -EnableException -OutVariable collected -WarningVariable warnings -WarningAction SilentlyContinue
            } catch {
                $caught = $PSItem
            }
            @($warnings).Count | Should -Be 1
            "$($warnings[0])" | Should -Match "\[Get-DbaDbccProcCache\] Failure \| Error connecting to \[$missingInstance\]: "
            $caught.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaDbccProcCache*"
            "$($caught.CategoryInfo.Category)" | Should -BeExactly "ConnectionError"
            "$($caught.TargetObject)" | Should -BeExactly $missingInstance
            # The line names the server; the caught record stays the server's own message.
            $caught.Exception.Message | Should -Not -BeLike "*Error connecting to*"
            @($collected).Count | Should -Be 0
        }
    }

    # In a runspace of its own, where Streams.Warning can be read and nothing else sets a preference. Points 5 and 6 of the section named above.
    Context "The warning stream of a failed connect" {
        BeforeAll {
            $streamLine = "\[Get-DbaDbccProcCache\] Failure \| Error connecting to \[$missingInstance\]: "
            $streamState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $streamRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($streamState)
            $streamRunspace.Open()
            $streamShell = [System.Management.Automation.PowerShell]::Create()
            $streamShell.Runspace = $streamRunspace
            $streamModulePath = (Get-Module dbatools | Where-Object ModuleType -eq Script | Select-Object -First 1).Path
            $null = $streamShell.AddCommand("Import-Module").AddParameter("Name", $streamModulePath).AddParameter("ErrorAction", "Stop").Invoke()

            function NativeProcCacheStreamCall {
                param([string]$Script)
                $streamShell.Commands.Clear()
                $streamShell.Streams.Warning.Clear()
                $null = $streamShell.AddScript($Script).AddArgument($missingInstance)
                $output = @($streamShell.Invoke())
                [pscustomobject]@{
                    Lines    = @($output | Where-Object { $PSItem.psobject.BaseObject -is [string] } | ForEach-Object { "$PSItem" })
                    Merged   = @($output | Where-Object { $PSItem.psobject.BaseObject -is [System.Management.Automation.WarningRecord] } | ForEach-Object { $PSItem.Message })
                    Warnings = @($streamShell.Streams.Warning | ForEach-Object { $PSItem.Message })
                }
            }
        }

        AfterAll {
            $streamShell.Dispose()
            $streamRunspace.Dispose()
        }

        It "holds the one line in the warning stream of a plain call, which goes on" {
            $call = NativeProcCacheStreamCall -Script 'param($Target) Get-DbaDbccProcCache -SqlInstance $Target; "next statement"'
            $call.Warnings.Count | Should -Be 1
            $call.Warnings[0] | Should -Match $streamLine
            $call.Lines | Should -Contain "next statement"
        }

        It "merges the one line under 3>&1 on a plain call" {
            $call = NativeProcCacheStreamCall -Script 'param($Target) Get-DbaDbccProcCache -SqlInstance $Target 3>&1; "next statement"'
            $call.Merged.Count | Should -Be 1
            $call.Merged[0] | Should -Match $streamLine
            $call.Warnings.Count | Should -Be 0
            $call.Lines | Should -Contain "next statement"
        }

        It "displays nothing under -EnableException, and -WarningVariable holds the one line" -Tag "NativeChecklist:enable-exception" {
            $call = NativeProcCacheStreamCall -Script 'param($Target) try { Get-DbaDbccProcCache -SqlInstance $Target -EnableException -WarningVariable held 3>&1 } catch { "caught " + $PSItem.FullyQualifiedErrorId }; "held " + @($held).Count; foreach ($line in $held) { "line " + $line }'
            $call.Merged.Count | Should -Be 0
            $call.Warnings.Count | Should -Be 0
            @($call.Lines | Where-Object { $PSItem -like "caught dbatools_Get-DbaDbccProcCache*" }).Count | Should -Be 1
            $call.Lines | Should -Contain "held 1"
            @($call.Lines | Where-Object { $PSItem -like "line *" -and $PSItem -match $streamLine }).Count | Should -Be 1
        }

        It "leaves the warning stream empty under -EnableException" -Tag "NativeChecklist:enable-exception" {
            $call = NativeProcCacheStreamCall -Script 'param($Target) try { Get-DbaDbccProcCache -SqlInstance $Target -EnableException } catch { "caught " + $PSItem.FullyQualifiedErrorId }'
            $call.Warnings.Count | Should -Be 0
            @($call.Lines | Where-Object { $PSItem -like "caught dbatools_Get-DbaDbccProcCache*" }).Count | Should -Be 1
        }
    }

    Context "A null or empty -SqlInstance" {
        # null-instance, null-element, null-in-array and empty-array: the command's own binder refuses it.
        It "refuses <Name> at the binder, with no warning and no output" -ForEach @(
            @{ Name = "a null element"; Value = @($null, "unused"); Id = "ParameterArgumentValidationErrorNullNotAllowed"; Reason = "is null" }
            @{ Name = "a null value"; Value = $null; Id = "ParameterArgumentValidationErrorNullNotAllowed"; Reason = "is null" }
            @{ Name = "an empty array"; Value = @(); Id = "ParameterArgumentValidationErrorEmptyArrayNotAllowed"; Reason = "is an empty array" }
        ) {
            $caught = $null
            $warnings = $null
            $collected = $null
            try {
                $null = Get-DbaDbccProcCache -SqlInstance $Value -OutVariable collected -WarningVariable warnings -WarningAction SilentlyContinue
            } catch {
                $caught = $PSItem
            }
            $caught.FullyQualifiedErrorId | Should -BeLike "$Id,*"
            "$($caught.CategoryInfo.Category)" | Should -BeExactly "InvalidData"
            $caught.Exception.Message | Should -BeExactly "Cannot bind argument to parameter 'SqlInstance' because it $Reason."
            # A binder refusal may leave these unset; @($null) would count 1.
            $warnings | Should -BeNullOrEmpty
            $collected | Should -BeNullOrEmpty
        }
    }
}

Describe "Native Get-DbaDbccProcCache on Azure SQL Database" -Tag IntegrationTests {
    BeforeAll {
        $azureDatabase = $TestConfig.AzureSqlDbName
        $splatAzureConnection = @{
            SqlInstance     = $TestConfig.AzureSqlDbServer
            Database        = $azureDatabase
            SqlCredential   = $TestConfig.AzureSqlDbCred
            EnableException = $true
        }
        $azureServer = $null
        for ($attempt = 0; $attempt -le 6; $attempt++) {
            try {
                $azureServer = Connect-DbaInstance @splatAzureConnection
                break
            } catch {
                # A paused serverless database answers 40613 or times out (-2) while it resumes, and the lab's mobile
                # internet can drop a name lookup (11001, "No such host is known").
                $azureError = $PSItem.Exception
                $isResuming = $false
                while ($azureError) {
                    if ($azureError.Number -in 40613, -2, 11001) { $isResuming = $true }
                    $azureError = $azureError.InnerException
                }
                if (-not $isResuming -or $attempt -eq 6) { throw }
                Start-Sleep -Seconds 10
            }
        }
        $azureDenied = "*does not have permission to run DBCC proccache for database 'master'."
    }

    # Read-only. azure-to-database: the database's own admin may run it, and the instance name is null there.
    It "returns the row on a connection to the database, and leaves it there" -Tag "NativeChecklist:azure-sqldb" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $warnings = $null
        $result = @(Get-DbaDbccProcCache -SqlInstance $azureServer -WarningVariable warnings -WarningAction SilentlyContinue)
        @($warnings).Count | Should -Be 0
        $result.Count | Should -Be 1
        $result[0].PSObject.Properties.Name | Should -BeExactly @("ComputerName", "InstanceName", "SqlInstance", "Count", "Used", "Active", "CacheSize", "CacheUsed", "CacheActive")
        $result[0].ComputerName | Should -BeExactly $azureServer.ComputerName
        $result[0].InstanceName | Should -BeNullOrEmpty
        $result[0].SqlInstance | Should -BeExactly $azureServer.DomainInstanceName
        $result[0].Count | Should -BeOfType [long]
        $azureServer.ConnectionContext.CurrentDatabase | Should -BeExactly $azureDatabase
    }

    # azure-by-name and azure-by-name-ee: connected by name, the login reaches master, where it may not run the DBCC.
    It "warns of the refusal in master on a connection by name" {
        $warnings = $null
        $result = @(Get-DbaDbccProcCache -SqlInstance $TestConfig.AzureSqlDbServer -SqlCredential $TestConfig.AzureSqlDbCred -WarningVariable warnings -WarningAction SilentlyContinue)
        $result.Count | Should -Be 0
        @($warnings).Count | Should -Be 1
        "$warnings" | Should -BeLike "*Failure | An exception occurred while executing a Transact-SQL statement or batch.User*"
        "$warnings" | Should -BeLike $azureDenied
    }

    It "throws that refusal under -EnableException, with the server as its target" {
        $record = $null
        try {
            $null = Get-DbaDbccProcCache -SqlInstance $TestConfig.AzureSqlDbServer -SqlCredential $TestConfig.AzureSqlDbCred -EnableException -WarningAction SilentlyContinue
        } catch {
            $record = $PSItem
        }
        $record.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaDbccProcCache*"
        "$($record.TargetObject)" | Should -BeExactly $TestConfig.AzureSqlDbServer
        $record.Exception.Message | Should -BeLike $azureDenied
    }
}

Describe "Native Get-DbaDbccProcCache over SQL authentication" -Tag IntegrationTests {
    BeforeAll {
        $loginInstance = $TestConfig.InstanceSqlLogin
        $loginCred = $TestConfig.SqlLoginCred
        # Unique per leg and run: the instance is shared.
        $stamp = Get-Random
        $homeName = "dbatoolsci_npc_home_$stamp"
        $lowName = "dbatoolsci_npc_low_$stamp"
        $lowPassword = "Npc-$([guid]::NewGuid().ToString('N'))"
        $lowCred = New-Object System.Management.Automation.PSCredential -ArgumentList $lowName, (ConvertTo-SecureString -String $lowPassword -AsPlainText -Force)
        $denied = "An exception occurred while executing a Transact-SQL statement or batch.User 'guest' does not have permission to run DBCC proccache for database 'master'."
        $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
        $null = $loginServer.Query("CREATE DATABASE [$homeName];")
        $null = $loginServer.Query("CREATE LOGIN [$lowName] WITH PASSWORD = '$lowPassword', CHECK_POLICY = OFF;")
        $loginServer.Databases.Refresh()
        $null = $loginServer.Databases[$homeName].ExecuteNonQuery("CREATE USER [$lowName] FOR LOGIN [$lowName];")
    }

    AfterAll {
        foreach ($row in @($loginServer.Query("SELECT session_id FROM sys.dm_exec_sessions WHERE login_name = N'$lowName';"))) {
            $null = $loginServer.Query("KILL $($row.session_id);")
        }
        $null = $loginServer.Query("IF DB_ID(N'$homeName') IS NOT NULL ALTER DATABASE [$homeName] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;")
        $null = $loginServer.Query("IF DB_ID(N'$homeName') IS NOT NULL DROP DATABASE [$homeName];")
        $null = $loginServer.Query("IF SUSER_ID(N'$lowName') IS NOT NULL DROP LOGIN [$lowName];")
    }

    Context "SQL login" -Tag NativeChecklist:sql-login {
        It "works with -SqlCredential" {
            $result = @(Get-DbaDbccProcCache -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException)
            $result.Count | Should -Be 1
            $result[0].Count | Should -BeOfType [long]
        }

        It "fails cleanly without the credential: a warning and no output" {
            $warnings = $null
            $result = Get-DbaDbccProcCache -SqlInstance $loginInstance -WarningVariable warnings -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            @($warnings).Count | Should -Be 1
            "$($warnings[0])" | Should -Match ("\[Get-DbaDbccProcCache\] Failure \| Error connecting to \[" + [regex]::Escape($loginInstance) + "\]: Login failed")
        }

        It "throws the connection failure under -EnableException" {
            { Get-DbaDbccProcCache -SqlInstance $loginInstance -EnableException -WarningAction SilentlyContinue } | Should -Throw -ExpectedMessage "*Login failed*" -ErrorId "dbatools_Get-DbaDbccProcCache*"
        }
    }

    Context "A login that may not run the DBCC" {
        It "warns with the joined server messages and goes on to the next instance" {
            $warnings = $null
            $result = @(Get-DbaDbccProcCache -SqlInstance $loginInstance, $loginServer -SqlCredential $lowCred -WarningVariable warnings -WarningAction SilentlyContinue)
            @($warnings).Count | Should -Be 1
            "$warnings".EndsWith("[Get-DbaDbccProcCache] Failure | $denied", [System.StringComparison]::Ordinal) | Should -BeTrue
            $result.Count | Should -Be 1
        }

        It "throws the same text under -EnableException, with the server as its target" -Tag "NativeChecklist:enable-exception" {
            $record = $null
            try {
                $null = Get-DbaDbccProcCache -SqlInstance $loginInstance, $loginServer -SqlCredential $lowCred -EnableException -WarningAction SilentlyContinue
            } catch {
                $record = $PSItem
            }
            $record.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaDbccProcCache*"
            "$($record.CategoryInfo.Category)" | Should -BeExactly "NotSpecified"
            "$($record.TargetObject)" | Should -BeExactly $loginInstance
            $record.Exception.Message | Should -BeExactly $denied
            $record.Exception.InnerException | Should -BeOfType System.Management.Automation.MethodInvocationException
            $record.Exception.InnerException.Message | Should -BeExactly "Exception calling ""Query"" with ""1"" argument(s): ""$denied"""
        }

        It "keeps the warning and does not throw under -ErrorAction <Action>" -ForEach @(
            @{ Action = "Stop" }
            @{ Action = "SilentlyContinue" }
        ) {
            $warnings = $null
            $result = Get-DbaDbccProcCache -SqlInstance $loginInstance -SqlCredential $lowCred -ErrorAction $Action -WarningVariable warnings -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            @($warnings).Count | Should -Be 1
            "$warnings".EndsWith("Failure | $denied", [System.StringComparison]::Ordinal) | Should -BeTrue
        }
    }

    # caller-plain-user and caller-db-owner: this one needs no switch to master, so it runs in the caller's own database.
    Context "A caller's connection in its own database" {
        It "reports the server's refusal to a plain user there, then gives a db_owner the row, and stays there" {
            $caller = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $lowCred -Database $homeName -NonPooledConnection -EnableException
            try {
                $warnings = $null
                $result = Get-DbaDbccProcCache -SqlInstance $caller -WarningVariable warnings -WarningAction SilentlyContinue
                $result | Should -BeNullOrEmpty
                @($warnings).Count | Should -Be 1
                "$warnings" | Should -BeLike "*Failure | An exception occurred while executing a Transact-SQL statement or batch.User '$lowName' does not have permission to run DBCC proccache for database '$homeName'."
                $caller.ConnectionContext.CurrentDatabase | Should -BeExactly $homeName
            } finally {
                $caller.ConnectionContext.Disconnect()
            }

            $null = $loginServer.Databases[$homeName].ExecuteNonQuery("ALTER ROLE db_owner ADD MEMBER [$lowName];")
            $caller = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $lowCred -Database $homeName -NonPooledConnection -EnableException
            try {
                @(Get-DbaDbccProcCache -SqlInstance $caller -EnableException).Count | Should -Be 1
                $caller.ConnectionContext.CurrentDatabase | Should -BeExactly $homeName
            } finally {
                $caller.ConnectionContext.Disconnect()
            }
        }
    }
}
