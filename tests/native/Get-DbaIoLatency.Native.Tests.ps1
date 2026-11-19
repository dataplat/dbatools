#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
# NativeChecklist: whatif-confirm N/A -- the pinned command does not declare SupportsShouldProcess, so it has no -WhatIf or -Confirm.
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaIoLatency",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe "Native Get-DbaIoLatency" -Tag IntegrationTests {
    BeforeAll {
        $iolServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $iolTag = [guid]::NewGuid().ToString("N").Substring(0, 10)
        $iolMissing = "nf" + [guid]::NewGuid().ToString("N").Substring(0, 12)
        $iolDisplay = "ComputerName,DatabaseId,DatabaseName,FileId,InstanceName,IoStall,IoStallRead,IoStallWrite,NumberOfBytesRead,NumberOfBytesWritten,NumberOfReads,NumberOfwrites,PhysicalName,SampleMilliseconds,SizeOnDiskBytes,SqlInstance"
        $iolNames = "ComputerName,InstanceName,SqlInstance,DatabaseId,DatabaseName,FileId,PhysicalName,NumberOfReads,IoStallRead,NumberOfwrites,IoStallWrite,IoStall,NumberOfBytesRead,NumberOfBytesWritten,SampleMilliseconds,SizeOnDiskBytes,FileHandle,ReadLatency,WriteLatency,Latency,AvgBPerRead,AvgBPerWrite,AvgBPerTransfer"

        # Independent read: the files sys.master_files lists for the DMV's rows, on the test's own connection, as
        # "database_id/file_id" keys with the physical name.
        $fileSql = "SELECT [vfs].[database_id], [vfs].[file_id], [mf].[physical_name], DB_NAME([vfs].[database_id]) AS [name] FROM sys.dm_io_virtual_file_stats (NULL,NULL) AS [vfs] INNER JOIN sys.master_files AS [mf] ON [vfs].[database_id] = [mf].[database_id] AND [vfs].[file_id] = [mf].[file_id]"
        function Get-NativeFileCatalog {
            param($Server)
            @($Server.Query($fileSql))
        }
        function Get-NativeFileKey {
            param($DatabaseId, $FileId)
            "$DatabaseId/$FileId"
        }
    }

    It "returns one object per database file the catalog lists, shaped as the pin shapes it" {
        # The other PowerShell edition's lane may create or drop databases on this instance meanwhile, so the catalog is
        # read before and after: every file in both reads comes back, and nothing outside them does.
        $catalog = Get-NativeFileCatalog $iolServer
        $results = @(Get-DbaIoLatency -SqlInstance $TestConfig.InstanceSingle -ErrorVariable iolErrors)
        $catalogAfter = Get-NativeFileCatalog $iolServer
        $iolErrors | Should -BeNullOrEmpty

        $beforeKeys = @($catalog | ForEach-Object { Get-NativeFileKey $PSItem.database_id $PSItem.file_id })
        $afterKeys = @($catalogAfter | ForEach-Object { Get-NativeFileKey $PSItem.database_id $PSItem.file_id })
        $resultKeys = @($results | ForEach-Object { Get-NativeFileKey $PSItem.DatabaseId $PSItem.FileId })
        @($beforeKeys | Where-Object { $PSItem -in $afterKeys -and $PSItem -notin $resultKeys }) | Should -BeNullOrEmpty
        @($resultKeys | Where-Object { $PSItem -notin $beforeKeys -and $PSItem -notin $afterKeys }) | Should -BeNullOrEmpty
        @($resultKeys | Select-Object -Unique).Count | Should -Be $results.Count

        foreach ($result in $results) {
            ($result.PSObject.Properties.Name -join ",") | Should -BeExactly $iolNames
            ($result.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") | Should -BeExactly $iolDisplay
            $result.ComputerName | Should -BeExactly $iolServer.ComputerName
            $result.InstanceName | Should -BeExactly $iolServer.ServiceName
            $result.SqlInstance | Should -BeExactly $iolServer.DomainInstanceName
        }

        # master's primary data file never moves while the test runs: its values come from the catalog.
        $masterRow = $catalog | Where-Object { $PSItem.database_id -eq 1 -and $PSItem.file_id -eq 1 }
        $master = $results | Where-Object { $PSItem.DatabaseId -eq 1 -and $PSItem.FileId -eq 1 }
        @($master).Count | Should -Be 1
        $master.DatabaseName | Should -BeExactly "master"
        $master.PhysicalName | Should -BeExactly $masterRow.physical_name
        $master.DatabaseId | Should -BeOfType [System.Int16]
        $master.FileId | Should -BeOfType [System.Int16]
        $master.NumberOfReads | Should -BeOfType [System.Int64]
        $master.FileHandle | Should -BeOfType [System.Byte]
        $master.NumberOfReads | Should -BeGreaterThan 0
        $master.ReadLatency | Should -Be ([System.Math]::Floor($master.IoStallRead / $master.NumberOfReads))
        $master.AvgBPerRead | Should -Be ([System.Math]::Floor($master.NumberOfBytesRead / $master.NumberOfReads))
    }

    It "returns the files of each piped instance and goes on past one that fails" -Tag "NativeChecklist:pipeline-multiple", "NativeChecklist:multi-instance-failure", "NativeChecklist:switch-false" {
        $warnings = @()
        $results = @(@($TestConfig.InstanceSingle, $iolMissing, $TestConfig.InstanceSingle) | Get-DbaIoLatency -EnableException:$false -WarningAction SilentlyContinue -WarningVariable warnings)
        @($results | Where-Object { $PSItem.DatabaseId -eq 1 -and $PSItem.FileId -eq 1 }).Count | Should -Be 2
        $warnings.Count | Should -Be 1
        "$($warnings[0])" | Should -Match ([regex]::Escape("[Get-DbaIoLatency] Failure | Error connecting to [$iolMissing]: "))
    }

    It "reads several named instances" {
        $results = @(Get-DbaIoLatency -SqlInstance $TestConfig.InstanceSingle, $TestConfig.InstanceSingle)
        @($results | Where-Object { $PSItem.DatabaseId -eq 1 -and $PSItem.FileId -eq 1 }).Count | Should -Be 2
    }

    It "throws the connection failure under -EnableException" -Tag "NativeChecklist:enable-exception" {
        $caught = $null
        try {
            $null = Get-DbaIoLatency -SqlInstance $iolMissing -EnableException -WarningAction SilentlyContinue
        } catch {
            $caught = $PSItem
        }
        $caught | Should -Not -BeNullOrEmpty
        $caught.CategoryInfo.Category | Should -Be "ConnectionError"
    }

    Context "A login without server state permission" {
        BeforeAll {
            # The pin runs $server.Query outside any try. A SQL login with no server permission connects, and the query of
            # sys.dm_io_virtual_file_stats then faults: it needs VIEW SERVER STATE (VIEW SERVER PERFORMANCE STATE from SQL
            # Server 2022 on), which a new login does not have.
            $lowName = "dbatoolsci_iol_${iolTag}_low"
            $lowPassword = "Iol-" + [guid]::NewGuid().ToString("N")
            $lowCred = New-Object System.Management.Automation.PSCredential -ArgumentList $lowName, (ConvertTo-SecureString -String $lowPassword -AsPlainText -Force)
            $null = $iolServer.Query("CREATE LOGIN [$lowName] WITH PASSWORD = N'$lowPassword', CHECK_POLICY = OFF, DEFAULT_DATABASE = [master];")

            function New-NativeLowServer {
                Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -SqlCredential $lowCred -EnableException
            }

            # Independent read: the record the module's Server.Query script method gives this login for the same
            # catalog read, called with one argument as the pin calls it.
            $lowReference = $null
            try {
                $null = (New-NativeLowServer).Query($fileSql)
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
            function Invoke-NativeLatencyOutsideTry {
                param([hashtable]$Arguments)
                $outsideState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
                $outsideType = (Get-Command Get-DbaIoLatency -CommandType Cmdlet).ImplementingType
                $outsideEntry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList "Get-DbaIoLatency", $outsideType, $null
                $outsideState.Commands.Add($outsideEntry)
                $outsideRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($outsideState)
                $outsideShell = [System.Management.Automation.PowerShell]::Create()
                $outsideOutput = New-Object "System.Management.Automation.PSDataCollection[psobject]"
                $outsideStop = $null
                try {
                    $outsideRunspace.Open()
                    $outsideShell.Runspace = $outsideRunspace
                    $null = $outsideShell.AddScript('param($Arguments) Get-DbaIoLatency @Arguments; "next statement"').AddArgument($Arguments)
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
            foreach ($row in @($iolServer.Query("SELECT session_id FROM sys.dm_exec_sessions WHERE login_name = N'$lowName';"))) {
                $null = $iolServer.Query("KILL $($row.session_id);")
            }
            $null = $iolServer.Query("IF SUSER_ID(N'$lowName') IS NOT NULL DROP LOGIN [$lowName];")
        }

        It "writes each instance's query fault and goes on, outside any try" {
            $outside = Invoke-NativeLatencyOutsideTry @{ SqlInstance = @((New-NativeLowServer), (New-NativeLowServer)) }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Warnings.Count | Should -Be 0
            $outside.Errors.Count | Should -Be 2
            foreach ($record in $outside.Errors) {
                Assert-NativeQueryFault -Record $record
            }
            ($outside.Output -join ",") | Should -BeExactly "next statement"
        }

        It "goes on to the next instance's files after a query fault" {
            $outside = Invoke-NativeLatencyOutsideTry @{ SqlInstance = @((New-NativeLowServer), $iolServer) }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            Assert-NativeQueryFault -Record $outside.Errors[0]
            @($outside.Output | Where-Object { $PSItem.DatabaseId -eq 1 -and $PSItem.FileId -eq 1 }).Count | Should -Be 1
            @($outside.Output)[-1] | Should -BeExactly "next statement"
        }

        It "stops at the first query fault under -EnableException" -Tag "NativeChecklist:enable-exception" {
            $outside = Invoke-NativeLatencyOutsideTry @{ SqlInstance = @((New-NativeLowServer), (New-NativeLowServer)); EnableException = $true }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            Assert-NativeQueryFault -Record $outside.Errors[0]
            ($outside.Output -join ",") | Should -BeExactly "next statement"
        }

        It "lets a caller's try catch the first query fault" {
            $first = New-NativeLowServer
            $second = New-NativeLowServer
            $callerOutput = @(try { Get-DbaIoLatency -SqlInstance $first, $second; "after" } catch { $_ })
            $callerOutput.Count | Should -Be 1
            $callerOutput[0] | Should -BeOfType [System.Management.Automation.ErrorRecord]
            Assert-NativeQueryFault -Record $callerOutput[0]
        }

        It "stops at the first query fault under -ErrorAction Stop, outside a try" {
            $outside = Invoke-NativeLatencyOutsideTry @{ SqlInstance = @((New-NativeLowServer), (New-NativeLowServer)); ErrorAction = "Stop" }
            $outside.Stop | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
            Assert-NativeQueryFault -Record $outside.Stop.ErrorRecord
            $outside.Output.Count | Should -Be 0
        }
    }

    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
            # Every leg shares this instance at once, so this context creates nothing: it reads the instance's files as
            # they are and compares them with the catalog, read on the test's own SQL-login connection before and after.
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
        }

        It "works with -SqlCredential" {
            $loginCatalog = @(Get-NativeFileCatalog $loginServer | ForEach-Object { Get-NativeFileKey $PSItem.database_id $PSItem.file_id })
            $result = @(Get-DbaIoLatency -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException -ErrorVariable loginErrors)
            $loginCatalogAfter = @(Get-NativeFileCatalog $loginServer | ForEach-Object { Get-NativeFileKey $PSItem.database_id $PSItem.file_id })
            $loginErrors | Should -BeNullOrEmpty
            $resultKeys = @($result | ForEach-Object { Get-NativeFileKey $PSItem.DatabaseId $PSItem.FileId })
            $resultKeys | Should -Not -BeNullOrEmpty
            @($loginCatalog | Where-Object { $PSItem -in $loginCatalogAfter -and $PSItem -notin $resultKeys }) | Should -BeNullOrEmpty
            @($resultKeys | Where-Object { $PSItem -notin $loginCatalog -and $PSItem -notin $loginCatalogAfter }) | Should -BeNullOrEmpty
            foreach ($row in $result) {
                $row.SqlInstance | Should -BeExactly $loginServer.DomainInstanceName
            }
        }

        It "fails cleanly without the credential: a warning and no output" {
            $warnings = @()
            $result = Get-DbaIoLatency -SqlInstance $loginInstance -WarningVariable warnings -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            $warnings | Should -Not -BeNullOrEmpty
        }

        It "throws without the credential under -EnableException, as the pinned Stop-Function does" {
            { Get-DbaIoLatency -SqlInstance $loginInstance -EnableException -WarningAction SilentlyContinue } | Should -Throw
        }
    }

    Context "Azure SQL Database" -Tag NativeChecklist:azure-sqldb {
        BeforeAll {
            # sys.dm_io_virtual_file_stats applies to Azure SQL Database, sys.master_files does not; sys.database_files
            # lists the database's own files there.
            # https://learn.microsoft.com/sql/relational-databases/system-dynamic-management-objects/sys-dm-io-virtual-file-stats-transact-sql
            # https://learn.microsoft.com/sql/relational-databases/system-catalog-views/sys-master-files-transact-sql
            # https://learn.microsoft.com/sql/relational-databases/system-catalog-views/sys-database-files-transact-sql
            # The command reports the database's files there (correction azure-files).
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
            # Independent read on the same connection: the database, and those of its files the DMV reports statistics for
            # (sys.database_files may list a file the DMV does not, and the pinned inner join keeps only the DMV's files).
            $azureDatabase = @($azure.Query("SELECT DB_ID() AS [id], DB_NAME() AS [name];"))[0]
            $azureFiles = @($azure.Query("SELECT [file_id], [physical_name] FROM sys.database_files WHERE [file_id] IN (SELECT [file_id] FROM sys.dm_io_virtual_file_stats (DB_ID(), NULL));"))
        }

        AfterAll {
            if ($azure) { $azure.ConnectionContext.Disconnect() }
        }

        It "returns one object per file of the Azure SQL Database, with its physical name" {
            $azure.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
            $azureWarnings = @()
            $rows = @(Get-DbaIoLatency -SqlInstance $azure -WarningAction SilentlyContinue -WarningVariable azureWarnings -ErrorVariable azureErrors -ErrorAction SilentlyContinue)
            $azureErrors | Should -BeNullOrEmpty
            $azureWarnings | Should -BeNullOrEmpty
            $azureFiles | Should -Not -BeNullOrEmpty
            $rows.Count | Should -Be $azureFiles.Count
            foreach ($file in $azureFiles) {
                $row = @($rows | Where-Object FileId -eq $file.file_id)
                $row.Count | Should -Be 1
                $row[0].PhysicalName | Should -BeExactly $file.physical_name
                $row[0].DatabaseId | Should -Be $azureDatabase.id
                $row[0].DatabaseName | Should -BeExactly $azureDatabase.name
                ($row[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") | Should -BeExactly $iolDisplay
            }
        }

        It "reads Azure SQL Database under -EnableException and goes on to the next instance" {
            $azure.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
            $rows = @(Get-DbaIoLatency -SqlInstance $azure, $iolServer -EnableException)
            @($rows | Where-Object SqlInstance -eq $iolServer.DomainInstanceName | Where-Object { $PSItem.DatabaseId -eq 1 -and $PSItem.FileId -eq 1 }).Count | Should -Be 1
            @($rows | Where-Object DatabaseName -eq $azureDatabase.name).Count | Should -Be $azureFiles.Count
        }
    }
}
