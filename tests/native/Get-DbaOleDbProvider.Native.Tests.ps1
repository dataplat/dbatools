#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
# NativeChecklist: whatif-confirm N/A -- the pinned command does not declare SupportsShouldProcess, so it has no -WhatIf or -Confirm, and it changes nothing.
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaOleDbProvider",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe "Native Get-DbaOleDbProvider" -Tag IntegrationTests {
    BeforeAll {
        $oledbServer = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle -EnableException
        $oledbMissing = "nf" + [guid]::NewGuid().ToString("N").Substring(0, 12)
        $oledbDisplay = "ComputerName,InstanceName,SqlInstance,Name,Description,AllowInProcess,DisallowAdHocAccess,DynamicParameters,IndexAsAccessPath,LevelZeroOnly,NestedQueries,NonTransactedUpdates"
        $oledbFlags = "AllowInProcess", "DisallowAdHocAccess", "DynamicParameters", "IndexAsAccessPath", "LevelZeroOnly", "NestedQueries", "NonTransactedUpdates"

        # Independent read: the providers the engine itself lists, by name and description.
        function Get-NativeOleDbCatalog {
            param($Server)
            @($Server.Query("EXEC master.dbo.xp_enum_oledb_providers") | ForEach-Object {
                    [pscustomobject]@{ Name = $PSItem."Provider Name"; Description = $PSItem."Provider Description" }
                })
        }

        # The pin's decoration of each provider, against the catalog and the SMO object of the test's own connection.
        function Assert-NativeOleDbRows {
            param($Rows, $Server, $Catalog)
            $Rows = @($Rows)
            $Rows.Count | Should -BeGreaterThan 0
            $Server.Settings.OleDbProviderSettings.Refresh()
            foreach ($row in $Rows) {
                $row | Should -BeOfType [Microsoft.SqlServer.Management.Smo.OleDbProviderSettings]
                $listed = @($Catalog | Where-Object Name -eq $row.Name)
                $listed.Count | Should -Be 1
                $row.Description | Should -BeExactly $listed[0].Description
                $own = $Server.Settings.OleDbProviderSettings[$row.Name]
                foreach ($flag in $oledbFlags) {
                    $row.$flag | Should -Be $own.$flag -Because "$($row.Name) $flag"
                }
                $row.ComputerName | Should -BeExactly $Server.ComputerName
                $row.InstanceName | Should -BeExactly $Server.ServiceName
                $row.SqlInstance | Should -BeExactly $Server.DomainInstanceName
                $row.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join "," | Should -BeExactly $oledbDisplay
            }
        }

        $oledbCatalog = Get-NativeOleDbCatalog -Server $oledbServer
        $oledbNames = @($oledbCatalog.Name)
    }

    It "returns every provider the engine lists, in SMO's order, decorated as the pin decorates them" {
        $oledbNames.Count | Should -BeGreaterThan 1
        $results = @(Get-DbaOleDbProvider -SqlInstance $TestConfig.InstanceSingle -ErrorVariable oledbErrors -WarningVariable oledbWarnings)
        @($oledbErrors) | Should -BeNullOrEmpty
        @($oledbWarnings) | Should -BeNullOrEmpty
        @($results.Name | Sort-Object) -join "," | Should -BeExactly (@($oledbNames | Sort-Object) -join ",")
        $order = @(foreach ($own in $oledbServer.Settings.OleDbProviderSettings) { $own.Name })
        $results.Name -join "," | Should -BeExactly ($order -join ",")
        Assert-NativeOleDbRows -Rows $results -Server $oledbServer -Catalog $oledbCatalog
    }

    It "matches -Provider names ignoring case and returns nothing for a name the instance does not have" {
        $wanted = @($oledbNames | Sort-Object | Select-Object -First 2)
        $results = @(Get-DbaOleDbProvider -SqlInstance $TestConfig.InstanceSingle -Provider $wanted[1].ToUpperInvariant(), $wanted[0].ToLowerInvariant(), $oledbMissing)
        @($results.Name | Sort-Object) -join "," | Should -BeExactly ($wanted -join ",")
        Assert-NativeOleDbRows -Rows $results -Server $oledbServer -Catalog $oledbCatalog

        $oledbWarnings = @()
        @(Get-DbaOleDbProvider -SqlInstance $TestConfig.InstanceSingle -Provider $oledbMissing -WarningVariable oledbWarnings).Count | Should -Be 0
        @($oledbWarnings) | Should -BeNullOrEmpty
    }

    It "filters only when -Provider is true as the pin's if tests it: one empty name lists every provider, two names filter" {
        @(Get-DbaOleDbProvider -SqlInstance $TestConfig.InstanceSingle -Provider "").Count | Should -Be $oledbNames.Count
        $one = @(Get-DbaOleDbProvider -SqlInstance $TestConfig.InstanceSingle -Provider "", $oledbNames[0])
        $one.Name | Should -BeExactly $oledbNames[0]
    }

    It "decorates the same provider object again when it is read twice through one connection" {
        $first = Get-DbaOleDbProvider -SqlInstance $oledbServer -Provider $oledbNames[0]
        $second = Get-DbaOleDbProvider -SqlInstance $oledbServer -Provider $oledbNames[0]
        $second.SqlInstance | Should -BeExactly $first.SqlInstance
        @($second.PSObject.Properties | Where-Object Name -eq "SqlInstance").Count | Should -Be 1
    }

    It "binds SqlInstance, SqlCredential and Provider by position, as the pinned function's declaration order does" {
        $parameters = (Get-Command Get-DbaOleDbProvider).Parameters
        $parameters["SqlInstance"].ParameterSets["__AllParameterSets"].Position | Should -Be 0
        $parameters["SqlCredential"].ParameterSets["__AllParameterSets"].Position | Should -Be 1
        $parameters["Provider"].ParameterSets["__AllParameterSets"].Position | Should -Be 2
        (Get-Command Get-DbaOleDbProvider).DefaultParameterSet | Should -BeExactly "Default"
    }

    It "writes the pinned verbose line, which reads a global servername the function never assigns" {
        $saved = Get-Variable -Name servername -Scope Global -ErrorAction SilentlyContinue
        try {
            Remove-Variable -Name servername -Scope Global -ErrorAction SilentlyContinue
            $unset = @(Get-DbaOleDbProvider -SqlInstance $oledbServer -Provider $oledbMissing -Verbose 4>&1 | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] -and $PSItem.Message.Contains("Getting startup procedures for") })
            $unset.Count | Should -Be 1
            $unset[0].Message | Should -Match "\[Get-DbaOleDbProvider\] Getting startup procedures for\s*$"

            $global:servername = "nativeoledbglobal"
            $set = @(Get-DbaOleDbProvider -SqlInstance $oledbServer -Provider $oledbMissing -Verbose 4>&1 | Where-Object { $PSItem -is [System.Management.Automation.VerboseRecord] -and $PSItem.Message.Contains("Getting startup procedures for") })
            $set.Count | Should -Be 1
            $set[0].Message | Should -Match ([regex]::Escape("[Get-DbaOleDbProvider] Getting startup procedures for nativeoledbglobal") + '$')
        } finally {
            Remove-Variable -Name servername -Scope Global -ErrorAction SilentlyContinue
            if ($saved) { Set-Variable -Name servername -Scope Global -Value $saved.Value }
        }
    }

    It "returns the providers of each piped instance and goes on past one that fails" -Tag "NativeChecklist:pipeline-multiple", "NativeChecklist:multi-instance-failure", "NativeChecklist:switch-false" {
        $oledbWarnings = @()
        $results = @(@($TestConfig.InstanceSingle, $oledbMissing, $TestConfig.InstanceSingle) | Get-DbaOleDbProvider -Provider $oledbNames[0] -EnableException:$false -WarningAction SilentlyContinue -WarningVariable oledbWarnings)
        $results.Count | Should -Be 2
        @($results.Name | Select-Object -Unique) | Should -BeExactly $oledbNames[0]
        Assert-NativeOleDbRows -Rows $results -Server $oledbServer -Catalog $oledbCatalog
        $oledbWarnings.Count | Should -Be 1
        # One line naming the command, the failure message and the instance (brackets matched literally).
        "$($oledbWarnings[0])" | Should -Match ([regex]::Escape("[Get-DbaOleDbProvider] Failure | Error connecting to [$oledbMissing]: "))
    }

    It "throws the connection failure under -EnableException" -Tag "NativeChecklist:enable-exception" {
        $oledbCaught = $null
        try {
            $null = Get-DbaOleDbProvider -SqlInstance $oledbMissing -EnableException -WarningAction SilentlyContinue
        } catch {
            $oledbCaught = $PSItem
        }
        $oledbCaught | Should -Not -BeNullOrEmpty
        "$($oledbCaught.CategoryInfo.Category)" | Should -BeExactly "ConnectionError"
        $oledbCaught.TargetObject | Should -Not -BeNullOrEmpty
    }

    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException
            $loginCatalog = Get-NativeOleDbCatalog -Server $loginServer
        }

        It "works with -SqlCredential" {
            $results = @(Get-DbaOleDbProvider -SqlInstance $loginInstance -SqlCredential $loginCred -EnableException)
            @($results.Name | Sort-Object) -join "," | Should -BeExactly (@($loginCatalog.Name | Sort-Object) -join ",")
            Assert-NativeOleDbRows -Rows $results -Server $loginServer -Catalog $loginCatalog
        }

        It "fails cleanly without the credential: a warning and no output" {
            $oledbWarnings = @()
            $result = Get-DbaOleDbProvider -SqlInstance $loginInstance -WarningVariable oledbWarnings -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            $oledbWarnings | Should -Not -BeNullOrEmpty
        }

        It "throws without the credential under -EnableException, as the pinned Stop-Function does" {
            { Get-DbaOleDbProvider -SqlInstance $loginInstance -EnableException -WarningAction SilentlyContinue } | Should -Throw
        }
    }

    # harness-edits.md, "Engine error records in native ports (operator, 2026-11-12)", point 5: the provider enumeration fault
    # after a working connection, per mode, entry by entry; pin and port side by side in the item notes (point 6).
    Context "Provider enumeration faults" {
        BeforeAll {
            # The pin enumerates $server.Settings.OleDbProviderSettings outside any try. SMO lists the providers with
            # "insert #OLEDBProv ... EXECUTE master.dbo.sp_enum_oledb_providers" (its OLEDBProviderSetting enumerator), so a
            # SQL login whose master user is denied EXECUTE on that procedure connects, and the enumeration faults. sysadmin
            # ignores DENY, so the login has no server role. The login is a SQL login, and pool instances are not guaranteed to
            # allow SQL authentication, so it lives on the fixed mixed-mode instance. Unique per leg; dropped in AfterAll.
            $faultInstance = $TestConfig.InstanceSqlLogin
            $faultAdmin = Connect-DbaInstance -SqlInstance $faultInstance -SqlCredential $TestConfig.SqlLoginCred -EnableException
            $faultAdmin.ConnectionContext.ExecuteScalar("SELECT CONVERT(int, SERVERPROPERTY('IsIntegratedSecurityOnly'));") | Should -Be 0
            $faultName = "dbatoolsci_oledb_" + [guid]::NewGuid().ToString("N").Substring(0, 10)
            $faultPassword = "Ole-" + [guid]::NewGuid().ToString("N")
            $null = $faultAdmin.Query("CREATE LOGIN [$faultName] WITH PASSWORD = N'$faultPassword', CHECK_POLICY = OFF, DEFAULT_DATABASE = [master];")
            $null = $faultAdmin.Query("USE [master]; CREATE USER [$faultName] FOR LOGIN [$faultName]; DENY EXECUTE ON OBJECT::sys.sp_enum_oledb_providers TO [$faultName];")
            $faultCred = New-Object System.Management.Automation.PSCredential -ArgumentList $faultName, (ConvertTo-SecureString -String $faultPassword -AsPlainText -Force)
            # A record a compiled cmdlet writes or throws carries its type after the id.
            $faultSuffix = ",Dataplat.Dbatools.Commands.GetDbaOleDbProviderCommand"

            function New-NativeDeniedServer {
                Connect-DbaInstance -SqlInstance $faultInstance -SqlCredential $faultCred -EnableException
            }

            # The pin's statement is "foreach ($oledbprovider in $providers)" over the collection: the same enumeration by the
            # engine, on a connection of the same login, is the reference record on this leg.
            $faultReference = $null
            try {
                foreach ($faultProvider in (New-NativeDeniedServer).Settings.OleDbProviderSettings) { }
            } catch {
                $faultReference = $PSItem
            }

            # The port's record is the reference record; its id carries the cmdlet type the engine adds (Child-command error
            # owner, point 1) and its Activity is the port's own name (Engine error records, point 1).
            function Assert-NativeEnumerationFault($Record) {
                $Record | Should -BeOfType System.Management.Automation.ErrorRecord
                $Record.FullyQualifiedErrorId | Should -BeExactly ((($faultReference.FullyQualifiedErrorId -split ",")[0]) + $faultSuffix)
                $Record.Exception.GetType().FullName | Should -BeExactly $faultReference.Exception.GetType().FullName
                $Record.Exception.Message | Should -BeExactly $faultReference.Exception.Message
                "$($Record.CategoryInfo.Category)" | Should -BeExactly "$($faultReference.CategoryInfo.Category)"
                $Record.CategoryInfo.Reason | Should -BeExactly $faultReference.CategoryInfo.Reason
                "$($Record.TargetObject)" | Should -BeExactly "$($faultReference.TargetObject)"
                $portInner = $Record.Exception.InnerException
                $referenceInner = $faultReference.Exception.InnerException
                while ($null -ne $referenceInner) {
                    $portInner | Should -Not -BeNullOrEmpty
                    $portInner.GetType().FullName | Should -BeExactly $referenceInner.GetType().FullName
                    $portInner.Message | Should -BeExactly $referenceInner.Message
                    $portInner = $portInner.InnerException
                    $referenceInner = $referenceInner.InnerException
                }
                $portInner | Should -BeNullOrEmpty
            }
            # The entries a call added to the global $Error, newest first, in a caller's try inside the It.
            function Get-NativeErrorHead {
                if ($global:Error.Count -gt 0) { $global:Error[0] }
            }
            function Get-NativeAddedErrors($head) {
                $added = New-Object System.Collections.ArrayList
                foreach ($entry in $global:Error) {
                    if ($null -ne $head -and [object]::ReferenceEquals($entry, $head)) { break }
                    $null = $added.Add($entry)
                }
                $added.ToArray()
            }

            # A Pester It runs its body inside a try, so a call outside any try needs a runspace of its own. Returns the
            # output, the error stream, the -ErrorVariable and $Error entries (the runspace's own, newest first) and the stop.
            function Invoke-NativeOleDbOutsideTry {
                param([hashtable]$Arguments)
                $outsideState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
                $outsideType = (Get-Command Get-DbaOleDbProvider -CommandType Cmdlet).ImplementingType
                $outsideEntry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList "Get-DbaOleDbProvider", $outsideType, $null
                $outsideState.Commands.Add($outsideEntry)
                $outsideRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($outsideState)
                $outsideShell = [System.Management.Automation.PowerShell]::Create()
                $outsideOutput = New-Object "System.Management.Automation.PSDataCollection[psobject]"
                $outsideStop = $null
                try {
                    $outsideRunspace.Open()
                    $outsideShell.Runspace = $outsideRunspace
                    $null = $outsideShell.AddScript('param($Arguments) $global:oledbFaults = @(); Get-DbaOleDbProvider @Arguments -ErrorVariable oledbFaults; "next statement"').AddArgument($Arguments)
                    try {
                        $null = $outsideShell.Invoke($null, $outsideOutput)
                    } catch {
                        $outsideStop = $PSItem.Exception.InnerException
                    }
                    $streamErrors = @($outsideShell.Streams.Error)
                    $reader = [System.Management.Automation.PowerShell]::Create()
                    $reader.Runspace = $outsideRunspace
                    $variableEntries = @($reader.AddScript('$global:oledbFaults').Invoke())
                    $reader.Commands.Clear()
                    $historyEntries = @($reader.AddScript('$global:Error').Invoke())
                    $reader.Dispose()
                    [pscustomobject]@{
                        Output   = @($outsideOutput | Where-Object { $PSItem.PSObject.BaseObject -isnot [string] })
                        Text     = @($outsideOutput | Where-Object { $PSItem.PSObject.BaseObject -is [string] })
                        Errors   = $streamErrors
                        Variable = @($variableEntries | ForEach-Object { $PSItem.PSObject.BaseObject })
                        History  = @($historyEntries | ForEach-Object { $PSItem.PSObject.BaseObject })
                        Stop     = $outsideStop
                    }
                } finally {
                    $outsideShell.Dispose()
                    $outsideRunspace.Dispose()
                }
            }
        }

        AfterAll {
            foreach ($row in @($faultAdmin.Query("SELECT session_id FROM sys.dm_exec_sessions WHERE login_name = N'$faultName';"))) {
                $null = $faultAdmin.Query("KILL $($row.session_id);")
            }
            $null = $faultAdmin.Query("USE [master]; IF USER_ID(N'$faultName') IS NOT NULL DROP USER [$faultName];")
            $null = $faultAdmin.Query("IF SUSER_ID(N'$faultName') IS NOT NULL DROP LOGIN [$faultName];")
            $faultAdmin.ConnectionContext.Disconnect()
        }

        It "faults the engine's own enumeration of the providers for the denied login" {
            $faultReference | Should -Not -BeNullOrEmpty
            $faultReference.Exception.GetBaseException().Message | Should -BeLike "*EXECUTE permission was denied*sp_enum_oledb_providers*"
        }

        It "writes the enumeration fault for each instance and goes on, outside any try" {
            $outside = Invoke-NativeOleDbOutsideTry @{ SqlInstance = @((New-NativeDeniedServer), (New-NativeDeniedServer)) }
            $outside.Stop | Should -BeNullOrEmpty
            ($outside.Text -join ",") | Should -BeExactly "next statement"
            $outside.Output.Count | Should -Be 0
            $outside.Errors.Count | Should -Be 2
            $outside.Variable.Count | Should -Be 2
            $outside.History.Count | Should -Be 2
            foreach ($record in @($outside.Errors) + @($outside.Variable) + @($outside.History)) {
                Assert-NativeEnumerationFault $record
            }
        }

        It "writes one fault per read with -Provider, the filter's and the foreach's, outside any try" {
            $outside = Invoke-NativeOleDbOutsideTry @{ SqlInstance = (New-NativeDeniedServer); Provider = $oledbNames[0] }
            $outside.Stop | Should -BeNullOrEmpty
            ($outside.Text -join ",") | Should -BeExactly "next statement"
            $outside.Output.Count | Should -Be 0
            $outside.Errors.Count | Should -Be 2
            $outside.Variable.Count | Should -Be 2
            $outside.History.Count | Should -Be 2
            foreach ($record in @($outside.Errors) + @($outside.Variable) + @($outside.History)) {
                Assert-NativeEnumerationFault $record
            }
        }

        It "keeps the faults in -ErrorVariable and `$Error without showing them under -ErrorAction SilentlyContinue" {
            $outside = Invoke-NativeOleDbOutsideTry @{ SqlInstance = @((New-NativeDeniedServer), (New-NativeDeniedServer)); ErrorAction = "SilentlyContinue" }
            $outside.Stop | Should -BeNullOrEmpty
            ($outside.Text -join ",") | Should -BeExactly "next statement"
            $outside.Output.Count | Should -Be 0
            $outside.Errors.Count | Should -Be 0
            $outside.Variable.Count | Should -Be 2
            $outside.History.Count | Should -Be 2
            foreach ($record in @($outside.Variable) + @($outside.History)) {
                Assert-NativeEnumerationFault $record
            }
        }

        It "stops at the first fault under -EnableException, outside any try" -Tag "NativeChecklist:enable-exception" {
            $outside = Invoke-NativeOleDbOutsideTry @{ SqlInstance = @((New-NativeDeniedServer), (New-NativeDeniedServer)); EnableException = $true }
            $outside.Stop | Should -BeNullOrEmpty
            ($outside.Text -join ",") | Should -BeExactly "next statement"
            $outside.Output.Count | Should -Be 0
            $outside.Errors.Count | Should -Be 1
            Assert-NativeEnumerationFault $outside.Errors[0]
            $outside.Variable.Count | Should -Be 1
            $outside.Variable[0].GetType().FullName | Should -BeExactly "System.Management.Automation.CmdletInvocationException"
            Assert-NativeEnumerationFault $outside.Variable[0].ErrorRecord
            $outside.History.Count | Should -Be 1
            Assert-NativeEnumerationFault $outside.History[0]
        }

        It "stops the script at the first fault under -ErrorAction Stop, outside any try" {
            $outside = Invoke-NativeOleDbOutsideTry @{ SqlInstance = @((New-NativeDeniedServer), (New-NativeDeniedServer)); ErrorAction = "Stop" }
            $outside.Stop | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
            Assert-NativeEnumerationFault $outside.Stop.ErrorRecord
            $outside.Text.Count | Should -Be 0
            $outside.Output.Count | Should -Be 0
            $outside.Variable.Count | Should -Be 1
            $outside.Variable[0].GetType().FullName | Should -BeExactly "System.Management.Automation.ActionPreferenceStopException"
            Assert-NativeEnumerationFault $outside.Variable[0].ErrorRecord
            $outside.History.Count | Should -Be 2
            $outside.History[0].GetType().FullName | Should -BeExactly "System.Management.Automation.ActionPreferenceStopException"
            Assert-NativeEnumerationFault $outside.History[0].ErrorRecord
            Assert-NativeEnumerationFault $outside.History[1]
        }

        It "lets a caller's try catch the first fault and does not go on, EnableException <EnableException>" -ForEach @(
            @{ EnableException = $false }
            @{ EnableException = $true }
        ) {
            $errors = @()
            $caught = $null
            $after = $false
            $rows = @()
            $head = Get-NativeErrorHead
            try {
                $rows = @(Get-DbaOleDbProvider -SqlInstance (New-NativeDeniedServer), $TestConfig.InstanceSingle -EnableException:$EnableException -ErrorVariable errors)
                $after = $true
            } catch { $caught = $PSItem }
            $added = @(Get-NativeAddedErrors $head)
            $after | Should -BeFalse
            $rows.Count | Should -Be 0
            Assert-NativeEnumerationFault $caught
            @($errors).Count | Should -Be 1
            $errors[0].GetType().FullName | Should -BeExactly "System.Management.Automation.CmdletInvocationException"
            Assert-NativeEnumerationFault $errors[0].ErrorRecord
            $added.Count | Should -Be 1
            Assert-NativeEnumerationFault $added[0]
        }
    }

    Context "Azure SQL Database" -Tag NativeChecklist:azure-sqldb {
        BeforeAll {
            # OLE DB providers serve linked servers and distributed queries (OPENDATASOURCE, OPENQUERY), none of which Azure SQL
            # Database has: https://learn.microsoft.com/sql/relational-databases/linked-servers/linked-servers-database-engine
            # ("Linked servers aren't available in Azure SQL Database") and
            # https://learn.microsoft.com/azure/azure-sql/database/features-comparison (OPENDATASOURCE, OPENQUERY: No).
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

        # Fleet.md step 4 (operator, 2026-10-28): a command Azure SQL Database cannot support refuses it as Connect-DbaInstance
        # -AzureUnsupported does (correction azure-refusal).
        It "refuses Azure SQL Database, which has no OLE DB providers, and goes on to the next instance" {
            $azure.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
            foreach ($splat in @(@{ }, @{ Provider = $oledbNames[0] })) {
                $azureWarnings = @()
                $rows = @(Get-DbaOleDbProvider -SqlInstance $azure, $TestConfig.InstanceSingle @splat -EnableException:$false -WarningAction SilentlyContinue -WarningVariable azureWarnings -ErrorVariable azureErrors)
                $azureWarnings.Count | Should -Be 1
                "$($azureWarnings[0])" | Should -Match ([regex]::Escape("[Get-DbaOleDbProvider] Failure | ") + ".*" + [regex]::Escape("Azure SQL Database not supported"))
                @($rows | Where-Object SqlInstance -ne $oledbServer.DomainInstanceName).Count | Should -Be 0
                @($rows | Where-Object Name -eq $oledbNames[0]).Count | Should -Be 1
            }
        }

        It "throws the Azure SQL Database refusal under -EnableException" {
            $azure.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
            $azureCaught = $null
            try {
                $null = Get-DbaOleDbProvider -SqlInstance $azure -EnableException -WarningAction SilentlyContinue
            } catch {
                $azureCaught = $PSItem
            }
            $azureCaught | Should -Not -BeNullOrEmpty
            "$($azureCaught.Exception.Message)" | Should -Match ([regex]::Escape("Azure SQL Database not supported"))
            "$($azureCaught.CategoryInfo.Category)" | Should -BeExactly "ConnectionError"
        }
    }
}
