#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaDbFileGroup",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- The pinned command has no SupportsShouldProcess, WhatIf or Confirm parameters; it only reads filegroups.

Describe "Native Get-DbaDbFileGroup" -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $instance = $TestConfig.InstanceSingle
        $random = Get-Random
        $server = Connect-DbaInstance -SqlInstance $instance

        $fileGroupDb = "dbatoolsci_nfg_$random"
        $wildcardPattern = "dbatoolsci_nf?_$random*"
        $null = $server.Query("CREATE DATABASE [$fileGroupDb]; ALTER DATABASE [$fileGroupDb] ADD FILEGROUP [Test1]; ALTER DATABASE [$fileGroupDb] ADD FILEGROUP [Test2];")
        $server.Databases.Refresh()
        $fileGroupObject = Get-DbaDatabase -SqlInstance $instance -Database $fileGroupDb

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        $null = $server.Query("IF DB_ID(N'$fileGroupDb') IS NOT NULL BEGIN ALTER DATABASE [$fileGroupDb] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$fileGroupDb]; END;")
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Output" {
        It "returns the SMO filegroups in name order with the instance names and the pinned default view" {
            $expected = @($server.Query("SELECT name FROM [$fileGroupDb].sys.filegroups ORDER BY name;").name)
            $result = @(Get-DbaDbFileGroup -SqlInstance $instance -Database $fileGroupDb)
            ($result.Name -join ",") | Should -Be ($expected -join ",")
            $result[0] | Should -BeOfType Microsoft.SqlServer.Management.Smo.FileGroup
            $result[0].ComputerName | Should -Be $server.ComputerName
            $result[0].InstanceName | Should -Be $server.ServiceName
            $result[0].SqlInstance | Should -Be $server.DomainInstanceName
            (@($result[0].PSObject.Properties | Where-Object MemberType -eq "NoteProperty").Name -join ",") | Should -Be "ComputerName,InstanceName,SqlInstance"
            ($result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") | Should -Be "ComputerName,InstanceName,SqlInstance,Parent,FileGroupType,Name,Size"
            $result[0].Parent.Name | Should -Be $fileGroupDb
            $result[0].FileGroupType | Should -Be "RowsFileGroup"
            $result[0].Size | Should -BeGreaterThan 0
        }
    }

    Context "Selection" {
        It "matches -Database and -FileGroup in any case on both paths" {
            @(Get-DbaDbFileGroup -SqlInstance $instance -Database $fileGroupDb.ToUpperInvariant()).Count | Should -Be 3
            @($fileGroupObject | Get-DbaDbFileGroup -Database $fileGroupDb.ToUpperInvariant()).Count | Should -Be 3
            @(Get-DbaDbFileGroup -SqlInstance $instance -Database $fileGroupDb -FileGroup test1).Name | Should -Be "Test1"
        }

        It "keeps -FileGroup exact, as its help documents no wildcards" {
            @(Get-DbaDbFileGroup -SqlInstance $instance -Database $fileGroupDb -FileGroup "Test*").Count | Should -Be 0
        }

        It "selects nothing for a bound empty or null -FileGroup" {
            @(Get-DbaDbFileGroup -SqlInstance $instance -Database $fileGroupDb -FileGroup @()).Count | Should -Be 0
            @(Get-DbaDbFileGroup -SqlInstance $instance -Database $fileGroupDb -FileGroup $null).Count | Should -Be 0
        }

        It "selects nothing for a bound empty or null -Database on both paths" {
            @(Get-DbaDbFileGroup -SqlInstance $instance -Database @()).Count | Should -Be 0
            @(Get-DbaDbFileGroup -SqlInstance $instance -Database $null).Count | Should -Be 0
            @($fileGroupObject | Get-DbaDbFileGroup -Database @()).Count | Should -Be 0
            @($fileGroupObject | Get-DbaDbFileGroup -Database $null).Count | Should -Be 0
        }

        It "refuses a null or empty -SqlInstance as the nested Get-DbaDatabase binding does" {
            { Get-DbaDbFileGroup -SqlInstance $null } | Should -Throw -ExpectedMessage "Cannot bind argument to parameter 'SqlInstance' because it is null." -ErrorId "ParameterArgumentValidationErrorNullNotAllowed,*"
            { Get-DbaDbFileGroup -SqlInstance @() } | Should -Throw -ExpectedMessage "Cannot bind argument to parameter 'SqlInstance' because it is an empty array." -ErrorId "ParameterArgumentValidationErrorEmptyArrayNotAllowed,*"
        }

        It "refuses a -SqlInstance array holding a null element before it reads any instance" {
            # The list lives in this scope and takes objects and warnings alike, so what arrived before the throw stays countable.
            $nullFirst = @($null, $instance)
            $nullFirstSeen = New-Object System.Collections.ArrayList
            { Get-DbaDbFileGroup -SqlInstance $nullFirst 3>&1 | ForEach-Object { $null = $nullFirstSeen.Add($PSItem) } } | Should -Throw -ExpectedMessage "Cannot bind argument to parameter 'SqlInstance' because it is null." -ErrorId "ParameterArgumentValidationErrorNullNotAllowed,*"
            $nullFirstSeen.Count | Should -Be 0

            $nullLast = @($instance, $null)
            $nullLastSeen = New-Object System.Collections.ArrayList
            { Get-DbaDbFileGroup -SqlInstance $nullLast 3>&1 | ForEach-Object { $null = $nullLastSeen.Add($PSItem) } } | Should -Throw -ExpectedMessage "Cannot bind argument to parameter 'SqlInstance' because it is null." -ErrorId "ParameterArgumentValidationErrorNullNotAllowed,*"
            $nullLastSeen.Count | Should -Be 0
        }

        It "gives each refused -SqlInstance the identity of the pinned binding record" {
            # Measured on the pin on both editions: evidence/pin-instance-element-20261101.txt. The binder's own type is internal, so the
            # port carries its public base, and the engine names the compiled command in the id.
            $refusals = @(
                @{ Value = $null; ErrorId = "ParameterArgumentValidationErrorNullNotAllowed"; Problem = "null" }
                @{ Value = @(); ErrorId = "ParameterArgumentValidationErrorEmptyArrayNotAllowed"; Problem = "an empty array" }
                @{ Value = @($null, $instance); ErrorId = "ParameterArgumentValidationErrorNullNotAllowed"; Problem = "null" }
                @{ Value = @($instance, $null); ErrorId = "ParameterArgumentValidationErrorNullNotAllowed"; Problem = "null" }
            )
            foreach ($refusal in $refusals) {
                $record = $null
                try {
                    $null = Get-DbaDbFileGroup -SqlInstance $refusal.Value
                } catch {
                    $record = $PSItem
                }
                $record | Should -Not -BeNullOrEmpty
                $record.FullyQualifiedErrorId | Should -BeExactly "$($refusal.ErrorId),Dataplat.Dbatools.Commands.GetDbaDbFileGroupCommand"
                "$($record.CategoryInfo.Category)" | Should -BeExactly "InvalidData"
                $record.CategoryInfo.Reason | Should -BeExactly "ParameterBindingValidationException"
                $record.CategoryInfo.Activity | Should -BeExactly "Get-DbaDbFileGroup"
                $record.CategoryInfo.TargetName | Should -BeNullOrEmpty
                $record.CategoryInfo.TargetType | Should -BeNullOrEmpty
                $record.TargetObject | Should -BeNullOrEmpty
                $record.Exception.GetType().FullName | Should -BeExactly "System.Management.Automation.ParameterBindingException"
                $record.Exception.Message | Should -BeExactly "Cannot bind argument to parameter 'SqlInstance' because it is $($refusal.Problem)."
                $record.Exception.InnerException | Should -BeNullOrEmpty
            }
        }

        It "reads nothing for a null or empty pipeline" {
            @($null | Get-DbaDbFileGroup -WarningVariable warnings -WarningAction SilentlyContinue).Count | Should -Be 0
            $warnings | Should -BeNullOrEmpty
            @(@() | Get-DbaDbFileGroup -WarningVariable warnings -WarningAction SilentlyContinue).Count | Should -Be 0
            $warnings | Should -BeNullOrEmpty
        }

        It "reads nothing for a null -InputObject or a null record beside a named -SqlInstance" {
            @(Get-DbaDbFileGroup -SqlInstance $instance -InputObject $null).Count | Should -Be 0
            @($null | Get-DbaDbFileGroup -SqlInstance $instance).Count | Should -Be 0
        }

        It "warns about a null element of -InputObject and reads the rest" {
            $result = @(Get-DbaDbFileGroup -InputObject @($null, $fileGroupObject) -WarningVariable warnings -WarningAction SilentlyContinue)
            $result.Count | Should -Be 3
            ($warnings -join " ") | Should -BeLike "*Skipping database  on  because it is not accessible, so its filegroups cannot be read*"
        }

        It "reads piped databases and leaves a -SqlInstance beside them alone" {
            $result = @($fileGroupObject | Get-DbaDbFileGroup -SqlInstance "127.0.0.1,1" -WarningVariable warnings -WarningAction SilentlyContinue)
            $result.Count | Should -Be 3
            $warnings | Should -BeNullOrEmpty
        }

        It "warns without input with either EnableException value" -Tag "NativeChecklist:enable-exception", "NativeChecklist:switch-false" {
            foreach ($enable in $false, $true) {
                $result = @(Get-DbaDbFileGroup -EnableException:$enable -WarningVariable warnings -WarningAction SilentlyContinue)
                $result.Count | Should -Be 0
                ($warnings -join " ") | Should -BeLike "*You must specify either a SQL instance or supply an InputObject*"
            }
        }
    }

    Context "Wildcards in -Database" {
        It "expands a wildcard in -Database" {
            $result = @(Get-DbaDbFileGroup -SqlInstance $instance -Database $wildcardPattern)
            $result.Count | Should -Be 3
            ($result.Parent.Name | Sort-Object -Unique) | Should -Be $fileGroupDb
        }

        It "expands a wildcard in -Database on piped databases" {
            $result = @($fileGroupObject | Get-DbaDbFileGroup -Database $wildcardPattern)
            $result.Count | Should -Be 3
            ($result.Parent.Name | Sort-Object -Unique) | Should -Be $fileGroupDb
        }
    }

    Context "Pipeline input" {
        It "returns the filegroups of each piped instance once" -Tag "NativeChecklist:pipeline-multiple" {
            @($instance, $instance | Get-DbaDbFileGroup -Database $fileGroupDb).Count | Should -Be 6
        }

        It "reads a piped instance after a piped database" {
            @($fileGroupObject, $instance | Get-DbaDbFileGroup -Database $fileGroupDb).Count | Should -Be 6
        }

        It "reads a piped instance after a null record" {
            @($null, $instance | Get-DbaDbFileGroup -Database $fileGroupDb).Count | Should -Be 3
        }

        It "reads a piped database after a piped instance" {
            @($instance, $fileGroupObject | Get-DbaDbFileGroup -Database $fileGroupDb).Count | Should -Be 6
        }
    }

    # Binder section, point 3, with the StatementFault section's point 4: evidence/pin-filegroup-binder-20261103.txt, both editions.
    Context "The binding fault of the nested Get-DbaDatabase" {
        BeforeAll {
            $bindingNull = "Cannot bind argument to parameter 'SqlInstance' because it is null."
            $bindingEmpty = "Cannot bind argument to parameter 'SqlInstance' because it is an empty array."

            # A Pester It runs its body inside a try, so a call outside any try needs a runspace of its own.
            function Invoke-NativeOutsideTry {
                param([hashtable]$Arguments, [string]$Script = 'param($Arguments, $Target) Get-DbaDbFileGroup @Arguments; "next statement"')
                $outsideState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
                $outsideType = (Get-Command Get-DbaDbFileGroup -CommandType Cmdlet).ImplementingType
                $outsideEntry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList "Get-DbaDbFileGroup", $outsideType, $null
                $outsideState.Commands.Add($outsideEntry)
                $outsideRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($outsideState)
                $outsideShell = [System.Management.Automation.PowerShell]::Create()
                $outsideOutput = New-Object "System.Management.Automation.PSDataCollection[psobject]"
                $outsideStop = $null
                try {
                    $outsideRunspace.Open()
                    $outsideShell.Runspace = $outsideRunspace
                    $null = $outsideShell.AddScript($Script).AddArgument($Arguments).AddArgument($instance)
                    try {
                        $null = $outsideShell.Invoke($null, $outsideOutput)
                    } catch {
                        # The stop leaves the runspace's script through Invoke, as a method call's exception.
                        $outsideStop = $PSItem.Exception.InnerException
                    }
                    [pscustomobject]@{
                        Rows     = @($outsideOutput | Where-Object { $PSItem.psobject.BaseObject -is [Microsoft.SqlServer.Management.Smo.FileGroup] })
                        Next     = @($outsideOutput | Where-Object { "$($PSItem.psobject.BaseObject)" -ceq "next statement" }).Count -gt 0
                        Errors   = @($outsideShell.Streams.Error)
                        Warnings = @($outsideShell.Streams.Warning)
                        Stop     = $outsideStop
                    }
                } finally {
                    $outsideShell.Dispose()
                    $outsideRunspace.Dispose()
                }
            }

            function Assert-NativeBindingRecord {
                param($Record, [string]$Message, [string]$Stem, [string]$Activity)
                $Record.Exception.GetType().FullName | Should -BeExactly "System.Management.Automation.ParameterBindingException"
                $Record.Exception.Message | Should -BeExactly $Message
                $Record.FullyQualifiedErrorId | Should -BeLike "$Stem,*"
                "$($Record.CategoryInfo.Category)" | Should -BeExactly "InvalidData"
                $Record.CategoryInfo.Reason | Should -BeExactly "ParameterBindingValidationException"
                $Record.CategoryInfo.Activity | Should -BeExactly $Activity
                $Record.TargetObject | Should -BeNullOrEmpty
            }
        }

        It "outside any try, a plain call writes the record, reads no instance of that array and goes on: <Form>" -ForEach @(
            @{ Form = "null"; Stem = "ParameterArgumentValidationErrorNullNotAllowed" }
            @{ Form = "empty"; Stem = "ParameterArgumentValidationErrorEmptyArrayNotAllowed" }
            @{ Form = "null first"; Stem = "ParameterArgumentValidationErrorNullNotAllowed" }
            @{ Form = "null last"; Stem = "ParameterArgumentValidationErrorNullNotAllowed" }
        ) {
            $forms = @{ "null" = $null; "empty" = @(); "null first" = @($null, $instance); "null last" = @($instance, $null) }
            $expected = if ($Form -eq "empty") { $bindingEmpty } else { $bindingNull }
            $outside = Invoke-NativeOutsideTry @{ SqlInstance = $forms[$Form]; Database = $fileGroupDb }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            Assert-NativeBindingRecord -Record $outside.Errors[0] -Message $expected -Stem $Stem -Activity "Get-DbaDatabase"
            $outside.Warnings.Count | Should -Be 0
            $outside.Rows.Count | Should -Be 0
            $outside.Next | Should -BeTrue
        }

        It "outside any try, a piped array holding a null writes the record and the other records are read: <Form>" -ForEach @(
            @{ Form = "alone"; Rows = 0; Script = 'param($Arguments, $Target) $record = @($Target, $null); , $record | Get-DbaDbFileGroup @Arguments; "next statement"' }
            @{ Form = "first"; Rows = 3; Script = 'param($Arguments, $Target) $record = @($Target, $null); $record, $Target | Get-DbaDbFileGroup @Arguments; "next statement"' }
            @{ Form = "between"; Rows = 6; Script = 'param($Arguments, $Target) $record = @($Target, $null); $Target, $record, $Target | Get-DbaDbFileGroup @Arguments; "next statement"' }
        ) {
            $outside = Invoke-NativeOutsideTry @{ Database = $fileGroupDb } -Script $Script
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            Assert-NativeBindingRecord -Record $outside.Errors[0] -Message $bindingNull -Stem "ParameterArgumentValidationErrorNullNotAllowed" -Activity "Get-DbaDatabase"
            $outside.Warnings.Count | Should -Be 0
            $outside.Rows.Count | Should -Be $Rows
            $outside.Next | Should -BeTrue
        }

        It "outside any try, -EnableException ends the command at the record and the script goes on" -Tag "NativeChecklist:enable-exception" {
            $script = 'param($Arguments, $Target) $record = @($Target, $null); $record, $Target | Get-DbaDbFileGroup @Arguments; "next statement"'
            $outside = Invoke-NativeOutsideTry @{ Database = $fileGroupDb; EnableException = $true } -Script $script
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            Assert-NativeBindingRecord -Record $outside.Errors[0] -Message $bindingNull -Stem "ParameterArgumentValidationErrorNullNotAllowed" -Activity "Get-DbaDatabase"
            $outside.Rows.Count | Should -Be 0
            $outside.Next | Should -BeTrue
        }

        It "outside any try, -ErrorAction Stop turns the record into the stop PowerShell gives WriteError" {
            $script = 'param($Arguments, $Target) $record = @($Target, $null); $record, $Target | Get-DbaDbFileGroup @Arguments; "next statement"'
            $outside = Invoke-NativeOutsideTry @{ Database = $fileGroupDb; ErrorAction = "Stop" } -Script $script
            $outside.Stop | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
            Assert-NativeBindingRecord -Record $outside.Stop.ErrorRecord -Message $bindingNull -Stem "ParameterArgumentValidationErrorNullNotAllowed" -Activity "Get-DbaDbFileGroup"
            $outside.Rows.Count | Should -Be 0
            $outside.Next | Should -BeFalse
        }

        It "inside a caller's try, the catch receives the record and the command does not go on" {
            $record = @($instance, $null)
            $streamed = New-Object System.Collections.ArrayList
            $failure = $null
            $after = $false
            try {
                $instance, $record, $instance | Get-DbaDbFileGroup -Database $fileGroupDb | ForEach-Object { $null = $streamed.Add($PSItem) }
                $after = $true
            } catch {
                $failure = $PSItem
            }
            $failure | Should -Not -BeNullOrEmpty
            Assert-NativeBindingRecord -Record $failure -Message $bindingNull -Stem "ParameterArgumentValidationErrorNullNotAllowed" -Activity "Get-DbaDbFileGroup"
            $after | Should -BeFalse
            # The first instance has left; the one after the record is not read.
            $streamed.Count | Should -Be 3
        }

        It "under -EnableException inside a caller's try, the catch receives the record" -Tag "NativeChecklist:enable-exception" {
            $failure = $null
            try {
                $null = Get-DbaDbFileGroup -SqlInstance @($null, $instance) -Database $fileGroupDb -EnableException
            } catch {
                $failure = $PSItem
            }
            Assert-NativeBindingRecord -Record $failure -Message $bindingNull -Stem "ParameterArgumentValidationErrorNullNotAllowed" -Activity "Get-DbaDbFileGroup"
        }
    }

    Context "A failed instance" {
        It "continues past it without forwarding EnableException" -Tag "NativeChecklist:multi-instance-failure", "NativeChecklist:enable-exception", "NativeChecklist:switch-false" {
            $savedTimeout = [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout
            $listener = New-Object System.Net.Sockets.TcpListener -ArgumentList ([System.Net.IPAddress]::Loopback), 0
            try {
                $listener.Start()
                $badInstance = "127.0.0.1," + $listener.LocalEndpoint.Port
                [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout = 1
                foreach ($enable in $false, $true) {
                    $splatFailure = @{
                        SqlInstance     = @($badInstance, $server)
                        Database        = $fileGroupDb
                        EnableException = $enable
                        WarningAction   = "SilentlyContinue"
                        WarningVariable = "failureWarnings"
                    }
                    $result = @(Get-DbaDbFileGroup @splatFailure)
                    $result.Count | Should -Be 3
                    ($failureWarnings -join " ") | Should -BeLike "*Failure*"
                }
            } finally {
                [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout = $savedTimeout
                $listener.Stop()
            }
        }
    }
}

Describe "Native Get-DbaDbFileGroup on Azure SQL Database" -Tag IntegrationTests {
    It "reads the filegroups of an Azure SQL Database by -SqlInstance and by pipeline" -Tag "NativeChecklist:azure-sqldb" {
        $splatAzureConnection = @{
            SqlInstance     = $TestConfig.AzureSqlDbServer
            Database        = $TestConfig.AzureSqlDbName
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
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        # Read-only: nothing is created in the shared database. The connection's database is the Azure database.
        $azureExpected = @($azureServer.ConnectionContext.ExecuteWithResults("SELECT name FROM sys.filegroups ORDER BY name;").Tables[0].Rows | ForEach-Object { $PSItem.name })
        $splatAzureFileGroup = @{
            SqlInstance     = $azureServer
            Database        = $TestConfig.AzureSqlDbName
            EnableException = $true
        }
        $azureRows = @(Get-DbaDbFileGroup @splatAzureFileGroup)
        ($azureRows.Name -join ",") | Should -Be ($azureExpected -join ",")
        $azureRows[0].Parent.Name | Should -BeExactly $TestConfig.AzureSqlDbName
        $azureRows[0].SqlInstance | Should -BeExactly $azureServer.DomainInstanceName
        $azureRows[0].Size | Should -BeGreaterThan 0
        $azurePipedRows = @($azureServer.Databases[$TestConfig.AzureSqlDbName] | Get-DbaDbFileGroup -EnableException)
        ($azurePipedRows.Name -join ",") | Should -Be ($azureExpected -join ",")
    }
}

Describe "Native Get-DbaDbFileGroup over SQL authentication" -Tag IntegrationTests {
    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
        }

        It "works with -SqlCredential" {
            $splatLoginFileGroup = @{
                SqlInstance     = $loginInstance
                SqlCredential   = $loginCred
                Database        = "master"
                EnableException = $true
            }
            $loginRows = @(Get-DbaDbFileGroup @splatLoginFileGroup)
            $loginRows.Count | Should -Be 1
            $loginRows[0].Name | Should -Be "PRIMARY"
            $loginRows[0].Parent.Name | Should -Be "master"
        }

        It "fails cleanly without the credential: a warning and no output" {
            $result = Get-DbaDbFileGroup -SqlInstance $loginInstance -Database master -WarningVariable warnings -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            ($warnings -join " ") | Should -BeLike "*Failure*"
        }

        # As the pin measured: the connection failure belongs to the nested database gather, which is not given -EnableException.
        It "fails cleanly without the credential under -EnableException, as the pinned function does" {
            $result = Get-DbaDbFileGroup -SqlInstance $loginInstance -Database master -EnableException -WarningVariable warnings -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            ($warnings -join " ") | Should -BeLike "*Failure*"
        }
    }
}
