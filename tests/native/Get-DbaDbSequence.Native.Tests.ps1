#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaDbSequence",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- The pinned command has no SupportsShouldProcess, WhatIf or Confirm parameters, though its help text lists the last two; it only reads sequences.

Describe "Native Get-DbaDbSequence" -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $instance = $TestConfig.InstanceSingle
        $random = Get-Random
        $server = Connect-DbaInstance -SqlInstance $instance -NonPooledConnection
        $dbA = "dbatoolsci_nseq_a_$random"
        $dbB = "dbatoolsci_nseq_b_$random"
        $dbOff = "dbatoolsci_nseq_off_$random"
        $dbHeld = "dbatoolsci_nseq_held_$random"
        $wildcard = "dbatoolsci_nseq_?_$random"
        foreach ($name in $dbA, $dbB, $dbOff, $dbHeld) {
            $null = $server.Query("CREATE DATABASE [$name];")
        }
        $null = $server.Query("USE [$dbA]; EXEC('CREATE SCHEMA sch_one'); EXEC('CREATE SCHEMA sch_two'); CREATE SEQUENCE dbo.seq_one AS int; CREATE SEQUENCE sch_one.seq_one AS int; CREATE SEQUENCE sch_one.seq_two AS int START WITH 5 INCREMENT BY 2; CREATE SEQUENCE sch_two.seq_one AS int; CREATE SEQUENCE dbo.[seq*star] AS int;")
        foreach ($name in $dbB, $dbOff, $dbHeld) {
            $null = $server.Query("USE [$name]; CREATE SEQUENCE dbo.seq_one AS int;")
        }
        $null = $server.Query("ALTER DATABASE [$dbOff] SET OFFLINE WITH ROLLBACK IMMEDIATE;")
        $server.Databases.Refresh()
        $objectA = Get-DbaDatabase -SqlInstance $instance -Database $dbA
        $objectB = Get-DbaDatabase -SqlInstance $instance -Database $dbB

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

        # A Pester It runs its body inside a try, so a call outside any try needs a runspace of its own.
        function Invoke-NativeOutsideTry {
            param([hashtable]$Arguments, [string]$Script = 'param($Arguments, $Target) Get-DbaDbSequence @Arguments; "next statement"')
            $outsideState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $outsideType = (Get-Command Get-DbaDbSequence -CommandType Cmdlet).ImplementingType
            $outsideEntry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList "Get-DbaDbSequence", $outsideType, $null
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
                    Rows     = @($outsideOutput | Where-Object { $PSItem.psobject.BaseObject -is [Microsoft.SqlServer.Management.Smo.Sequence] })
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
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        foreach ($name in $dbA, $dbB, $dbOff, $dbHeld) {
            # This connection's own session may still be in a database a test's USE moved it to, and DROP refuses a database in use.
            $null = $server.Query("USE [master]; IF DB_ID(N'$name') IS NOT NULL BEGIN ALTER DATABASE [$name] SET ONLINE; ALTER DATABASE [$name] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$name]; END;")
        }
        $server.ConnectionContext.Disconnect()
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Output" {
        It "returns the SMO sequence with the pinned notes, default view and values" {
            $expected = $server.Query("USE [$dbA]; SELECT start_value, increment FROM sys.sequences WHERE name = N'seq_two';")
            $result = @(Get-DbaDbSequence -SqlInstance $instance -Database $dbA -Sequence seq_two)
            $result.Count | Should -Be 1
            $result[0] | Should -BeOfType Microsoft.SqlServer.Management.Smo.Sequence
            (@($result[0].PSObject.Properties | Where-Object MemberType -eq "NoteProperty").Name -join ",") | Should -Be "ComputerName,InstanceName,SqlInstance,Database"
            ($result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") | Should -Be "ComputerName,InstanceName,SqlInstance,Database,Schema,Name,DataType,StartValue,IncrementValue"
            $result[0].ComputerName | Should -Be $server.ComputerName
            $result[0].InstanceName | Should -Be $server.ServiceName
            $result[0].SqlInstance | Should -Be $server.DomainInstanceName
            $result[0].Database | Should -Be $dbA
            $result[0].Schema | Should -Be "sch_one"
            "$($result[0].DataType)" | Should -Be "int"
            "$($result[0].StartValue)" | Should -Be "$($expected.start_value)"
            "$($result[0].IncrementValue)" | Should -Be "$($expected.increment)"
        }

        It "keeps the notes on a second call over the same objects" {
            $first = @($objectA | Get-DbaDbSequence)
            $second = @($objectA | Get-DbaDbSequence)
            $second.Count | Should -Be $first.Count
            (@($second[0].PSObject.Properties | Where-Object MemberType -eq "NoteProperty").Name -join ",") | Should -Be "ComputerName,InstanceName,SqlInstance,Database"
        }
    }

    Context "Selection" {
        It "takes -Name as -Sequence and compares names and schemas without regard to case" {
            @(Get-DbaDbSequence -SqlInstance $instance -Database $dbB -Name SEQ_ONE).Count | Should -Be 1
            @(Get-DbaDbSequence -SqlInstance $instance -Database $dbA -Schema SCH_TWO).Count | Should -Be 1
            @(Get-DbaDbSequence -SqlInstance $instance -Database $dbA -Sequence seq_one -Schema sch_one).Count | Should -Be 1
        }

        It "treats -Sequence and -Schema as names, not patterns" {
            @(Get-DbaDbSequence -SqlInstance $instance -Database $dbA -Sequence "seq_*").Count | Should -Be 0
            @(Get-DbaDbSequence -SqlInstance $instance -Database $dbA -Schema "sch_*").Count | Should -Be 0
            @(Get-DbaDbSequence -SqlInstance $instance -Database $dbA -Sequence "seq*star").Name | Should -Be "seq*star"
        }

        It "reads all for a filter that is falsy, and none for two empty names" {
            foreach ($filter in @(""), @(), $null) {
                @(Get-DbaDbSequence -SqlInstance $instance -Database $dbB -Sequence $filter).Count | Should -Be 1
                @(Get-DbaDbSequence -SqlInstance $instance -Database $dbB -Schema $filter).Count | Should -Be 1
            }
            @(Get-DbaDbSequence -SqlInstance $instance -Database $dbB -Sequence "", "").Count | Should -Be 0
            @(Get-DbaDbSequence -SqlInstance $instance -Database $dbB -Schema "", "").Count | Should -Be 0
        }

        It "leaves piped databases unfiltered by -Database" {
            @($objectA | Get-DbaDbSequence -Database $dbB -Sequence seq_one).Database | Select-Object -Unique | Should -Be $dbA
        }

        It "skips an offline database with no message, named or piped" {
            $warnings = $null
            @(Get-DbaDbSequence -SqlInstance $instance -Database $dbOff -WarningVariable warnings -WarningAction SilentlyContinue).Count | Should -Be 0
            $warnings | Should -BeNullOrEmpty
            $offObject = $server.Databases[$dbOff]
            @(Get-DbaDbSequence -InputObject $offObject, $objectB -Sequence seq_one -WarningVariable warnings -WarningAction SilentlyContinue).Database | Should -Be $dbB
            $warnings | Should -BeNullOrEmpty
        }

        # Correction database-wildcards.
        It "expands a wildcard in -Database" {
            $names = @(Get-DbaDbSequence -SqlInstance $instance -Database $wildcard -Sequence seq_one).Database | Sort-Object -Unique
            ($names -join ",") | Should -Be (@($dbA, $dbB) -join ",")
        }
    }

    Context "Pipeline input" {
        # Correction piped-instance-repeat.
        It "returns the rows of each piped instance once" -Tag "NativeChecklist:pipeline-multiple" {
            @($instance, $instance | Get-DbaDbSequence -Database $dbB -Sequence seq_one).Count | Should -Be 2
        }

        # Correction named-instance-repeat.
        It "reads a named instance once beside piped databases" {
            $result = @($objectA, $objectB | Get-DbaDbSequence -SqlInstance $instance -Database $dbB -Sequence seq_one)
            (@($result | Where-Object Database -eq $dbA)).Count | Should -Be 3
            (@($result | Where-Object Database -eq $dbB)).Count | Should -Be 2
        }

        It "reads each piped record's own input, in order" {
            ((@($instance, $objectA, $instance | Get-DbaDbSequence -Database $dbB -Sequence seq_one).Database) -join ",") | Should -Be (@($dbB, $dbA, $dbA, $dbA, $dbB) -join ",")
            ((@($objectA, $instance | Get-DbaDbSequence -Database $dbB -Sequence seq_one).Database) -join ",") | Should -Be (@($dbA, $dbA, $dbA, $dbB) -join ",")
        }

        It "reads -InputObject and then a named instance" {
            ((@(Get-DbaDbSequence -InputObject $objectA -SqlInstance $instance -Database $dbB -Sequence seq_one).Database) -join ",") | Should -Be (@($dbA, $dbA, $dbA, $dbB) -join ",")
        }

        It "passes over a null element of -InputObject with no message" {
            $warnings = $null
            $result = @(Get-DbaDbSequence -InputObject @($null, $objectB) -WarningVariable warnings -WarningAction SilentlyContinue)
            $result.Count | Should -Be 1
            $warnings | Should -BeNullOrEmpty
        }
    }

    Context "Nothing to read" {
        It "warns for <Name> and goes on" -ForEach @(
            @{ Name = "no input"; Arguments = @{ } }
            @{ Name = "a null -SqlInstance"; Arguments = @{ SqlInstance = $null } }
            @{ Name = "an empty -SqlInstance"; Arguments = @{ SqlInstance = @() } }
            @{ Name = "a null -InputObject"; Arguments = @{ InputObject = $null } }
            @{ Name = "an empty -InputObject"; Arguments = @{ InputObject = @() } }
        ) {
            $outside = Invoke-NativeOutsideTry $Arguments
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Rows.Count | Should -Be 0
            $outside.Warnings.Count | Should -Be 1
            $outside.Warnings[0].Message | Should -Match "\[Get-DbaDbSequence\] You must pipe in a database or specify a SqlInstance$"
            $outside.Next | Should -BeTrue
        }

        It "throws that warning under -EnableException" -Tag "NativeChecklist:enable-exception" {
            { Get-DbaDbSequence -EnableException -WarningAction SilentlyContinue } | Should -Throw -ExpectedMessage "You must pipe in a database or specify a SqlInstance" -ErrorId "dbatools_Get-DbaDbSequence*"
        }

        It "warns for a null record and reads the next one" {
            $warnings = $null
            $result = @($null, $objectB | Get-DbaDbSequence -WarningVariable warnings -WarningAction SilentlyContinue)
            $result.Count | Should -Be 1
            @($warnings).Count | Should -Be 1
            $warnings = $null
            $result = @($null, $instance | Get-DbaDbSequence -Database $dbB -WarningVariable warnings -WarningAction SilentlyContinue)
            $result.Count | Should -Be 1
            @($warnings).Count | Should -Be 1
        }

        It "does nothing for an empty pipeline" {
            @(@() | Get-DbaDbSequence -SqlInstance $instance -Database $dbB).Count | Should -Be 0
        }
    }

    Context "The binding fault of the nested Get-DbaDatabase" {
        BeforeAll {
            $bindingNull = "Cannot bind argument to parameter 'SqlInstance' because it is null."
            function Assert-NativeBindingRecord {
                param($Record, [string]$Activity)
                $Record.Exception.GetType().FullName | Should -BeExactly "System.Management.Automation.ParameterBindingException"
                $Record.Exception.Message | Should -BeExactly $bindingNull
                $Record.FullyQualifiedErrorId | Should -BeLike "ParameterArgumentValidationErrorNullNotAllowed,*"
                "$($Record.CategoryInfo.Category)" | Should -BeExactly "InvalidData"
                $Record.CategoryInfo.Reason | Should -BeExactly "ParameterBindingValidationException"
                $Record.CategoryInfo.Activity | Should -BeExactly $Activity
                $Record.TargetObject | Should -BeNullOrEmpty
            }
        }

        It "outside any try, a plain call writes the record, reads no instance of that array and goes on: <Form>" -ForEach @(
            @{ Form = "null first" }
            @{ Form = "null last" }
            @{ Form = "two nulls" }
        ) {
            $forms = @{ "null first" = @($null, $instance); "null last" = @($instance, $null); "two nulls" = @($null, $null) }
            $outside = Invoke-NativeOutsideTry @{ SqlInstance = $forms[$Form]; Database = $dbB }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            Assert-NativeBindingRecord -Record $outside.Errors[0] -Activity "Get-DbaDatabase"
            $outside.Warnings.Count | Should -Be 0
            $outside.Rows.Count | Should -Be 0
            $outside.Next | Should -BeTrue
        }

        It "outside any try, the record's -InputObject is still read" {
            $outside = Invoke-NativeOutsideTry @{ SqlInstance = @($null, $instance); InputObject = $objectB }
            $outside.Errors.Count | Should -Be 1
            $outside.Rows.Count | Should -Be 1
            $outside.Next | Should -BeTrue
        }

        It "outside any try, a piped array holding a null writes the record and the next record is read" {
            $script = 'param($Arguments, $Target) $record = @($Target, $null); $record, $Target | Get-DbaDbSequence @Arguments; "next statement"'
            $outside = Invoke-NativeOutsideTry @{ Database = $dbB } -Script $script
            $outside.Errors.Count | Should -Be 1
            Assert-NativeBindingRecord -Record $outside.Errors[0] -Activity "Get-DbaDatabase"
            $outside.Rows.Count | Should -Be 1
            $outside.Next | Should -BeTrue
        }

        # Correction piped-instance-repeat.
        It "outside any try, a piped array holding a null between instances reads each instance once" {
            $script = 'param($Arguments, $Target) $record = @($Target, $null); $Target, $record, $Target | Get-DbaDbSequence @Arguments; "next statement"'
            $outside = Invoke-NativeOutsideTry @{ Database = $dbB } -Script $script
            $outside.Errors.Count | Should -Be 1
            $outside.Rows.Count | Should -Be 2
            $outside.Next | Should -BeTrue
        }

        It "outside any try, -EnableException ends the command at the record and the script goes on" -Tag "NativeChecklist:enable-exception" {
            $outside = Invoke-NativeOutsideTry @{ SqlInstance = @($null, $instance); Database = $dbB; EnableException = $true }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            Assert-NativeBindingRecord -Record $outside.Errors[0] -Activity "Get-DbaDatabase"
            $outside.Rows.Count | Should -Be 0
            $outside.Next | Should -BeTrue
        }

        It "outside any try, -ErrorAction Stop turns the record into the stop PowerShell gives WriteError" {
            $outside = Invoke-NativeOutsideTry @{ SqlInstance = @($null, $instance); Database = $dbB; ErrorAction = "Stop" }
            $outside.Stop | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
            Assert-NativeBindingRecord -Record $outside.Stop.ErrorRecord -Activity "Get-DbaDbSequence"
            $outside.Next | Should -BeFalse
        }

        It "inside a caller's try, the catch receives the record and the command does not go on" {
            $failure = $null
            $after = $false
            try {
                $null = Get-DbaDbSequence -SqlInstance @($null, $instance) -InputObject $objectB
                $after = $true
            } catch {
                $failure = $PSItem
            }
            Assert-NativeBindingRecord -Record $failure -Activity "Get-DbaDbSequence"
            $after | Should -BeFalse
        }
    }

    Context "A database whose sequences cannot be read" {
        BeforeAll {
            # A separate session holds the database in single-user mode, so reading its sequences faults. Objects read before that are what the command gets.
            $heldReader = Connect-DbaInstance -SqlInstance $instance -NonPooledConnection
            $heldObject = $heldReader.Databases[$dbHeld]
            $heldOther = $heldReader.Databases[$dbB]
            $null = $heldObject.IsAccessible
            $null = $heldOther.IsAccessible
            $holder = Connect-DbaInstance -SqlInstance $instance -NonPooledConnection
            $null = $holder.ConnectionContext.ExecuteNonQuery("USE [$dbHeld]; ALTER DATABASE [$dbHeld] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;")
            $held = @($heldObject, $heldOther)
            $enumerateMessage = 'The following exception occurred while trying to enumerate the collection: "An exception occurred while executing a Transact-SQL statement or batch.".'
        }

        AfterAll {
            $null = $holder.ConnectionContext.ExecuteNonQuery("USE [master]; ALTER DATABASE [$dbHeld] SET MULTI_USER;")
            $holder.ConnectionContext.Disconnect()
            $heldReader.ConnectionContext.Disconnect()
        }

        It "outside any try, writes a record for each attempt to read and reads the next database: <Name>" -ForEach @(
            @{ Name = "no filter"; Filters = @{ }; Records = 1 }
            @{ Name = "-Sequence"; Filters = @{ Sequence = "seq_one" }; Records = 2 }
            @{ Name = "-Schema"; Filters = @{ Schema = "dbo" }; Records = 2 }
            @{ Name = "both"; Filters = @{ Sequence = "seq_one"; Schema = "dbo" }; Records = 3 }
        ) {
            $outside = Invoke-NativeOutsideTry ($Filters + @{ InputObject = $held })
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be $Records
            foreach ($record in $outside.Errors) {
                $record.Exception | Should -BeOfType System.Management.Automation.ExtendedTypeSystemException
                $record.Exception.Message | Should -BeExactly $enumerateMessage
                $record.Exception.InnerException | Should -BeOfType Microsoft.SqlServer.Management.Common.ExecutionFailureException
                $record.FullyQualifiedErrorId | Should -BeLike "ExceptionInGetEnumerator*"
                "$($record.CategoryInfo.Category)" | Should -BeExactly "NotSpecified"
                $record.CategoryInfo.Reason | Should -BeExactly "ExtendedTypeSystemException"
                $record.TargetObject | Should -BeNullOrEmpty
            }
            $outside.Rows.Count | Should -Be 1
            $outside.Rows[0].Database | Should -Be $dbB
            $outside.Next | Should -BeTrue
        }

        It "outside any try, -EnableException ends the command at the record and the script goes on" -Tag "NativeChecklist:enable-exception" {
            $outside = Invoke-NativeOutsideTry @{ InputObject = $held; EnableException = $true }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            $outside.Rows.Count | Should -Be 0
            $outside.Next | Should -BeTrue
        }

        It "outside any try, -ErrorAction Stop turns the record into the stop PowerShell gives WriteError" {
            $outside = Invoke-NativeOutsideTry @{ InputObject = $held; ErrorAction = "Stop" }
            $outside.Stop | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
            $outside.Rows.Count | Should -Be 0
            $outside.Next | Should -BeFalse
        }

        It "inside a caller's try, the catch receives the record and the command does not go on" {
            $failure = $null
            $after = $false
            $rows = New-Object System.Collections.ArrayList
            try {
                Get-DbaDbSequence -InputObject $held | ForEach-Object { $null = $rows.Add($PSItem) }
                $after = $true
            } catch {
                $failure = $PSItem
            }
            $failure.FullyQualifiedErrorId | Should -BeLike "ExceptionInGetEnumerator*"
            $failure.Exception.Message | Should -BeExactly $enumerateMessage
            $after | Should -BeFalse
            $rows.Count | Should -Be 0
        }
    }

    Context "A failed instance" {
        It "warns for it and reads the next, also under -EnableException, which the nested call is not given" -Tag "NativeChecklist:multi-instance-failure", "NativeChecklist:enable-exception", "NativeChecklist:switch-false" {
            $savedTimeout = [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout
            $listener = New-Object System.Net.Sockets.TcpListener -ArgumentList ([System.Net.IPAddress]::Loopback), 0
            try {
                $listener.Start()
                $badInstance = "127.0.0.1," + $listener.LocalEndpoint.Port
                [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout = 1
                foreach ($enable in $false, $true) {
                    $splatFailure = @{
                        SqlInstance     = @($badInstance, $instance)
                        Database        = $dbB
                        EnableException = $enable
                        WarningAction   = "SilentlyContinue"
                        WarningVariable = "failureWarnings"
                    }
                    $result = @(Get-DbaDbSequence @splatFailure)
                    $result.Count | Should -Be 1
                    ($failureWarnings -join " ") | Should -BeLike "*Failure*"
                }
            } finally {
                [Dataplat.Dbatools.Connection.ConnectionHost]::SqlConnectionTimeout = $savedTimeout
                $listener.Stop()
            }
        }
    }
}

Describe "Native Get-DbaDbSequence on Azure SQL Database" -Tag IntegrationTests {
    BeforeAll {
        $splatAzureConnection = @{
            SqlInstance     = $TestConfig.AzureSqlDbServer
            Database        = $TestConfig.AzureSqlDbName
            SqlCredential   = $TestConfig.AzureSqlDbCred
            EnableException = $true
            WarningAction   = "SilentlyContinue"
        }
        $azureServer = $null
        for ($attempt = 0; $attempt -le 6 -and $null -eq $azureServer; $attempt++) {
            try {
                $azureServer = Connect-DbaInstance @splatAzureConnection
            } catch {
                # A paused serverless database answers 40613 or times out while it resumes, and the lab's mobile internet can drop a name lookup or stall.
                $azureError = $PSItem.Exception
                $isResuming = "$($azureError.Message)" -like "*timed out*"
                while ($azureError) {
                    if ($azureError.Number -in 40613, -2, 258, 11001 -or $azureError -is [System.TimeoutException]) { $isResuming = $true }
                    $azureError = $azureError.InnerException
                }
                if (-not $isResuming -or $attempt -eq 6) { throw }
                Start-Sleep -Seconds 10
            }
        }
        $azureSequence = "dbatoolsci_nseq_" + (Get-Random)
        $null = $azureServer.ConnectionContext.ExecuteNonQuery("CREATE SEQUENCE dbo.[$azureSequence] AS int;")
    }

    AfterAll {
        if ($azureServer) {
            $null = $azureServer.ConnectionContext.ExecuteNonQuery("IF OBJECT_ID(N'dbo.[$azureSequence]') IS NOT NULL DROP SEQUENCE dbo.[$azureSequence];")
            $azureServer.ConnectionContext.Disconnect()
        }
    }

    It "reads a sequence of an Azure SQL Database through a server object and by pipeline" -Tag "NativeChecklist:azure-sqldb" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $result = @(Get-DbaDbSequence -SqlInstance $azureServer -Sequence $azureSequence -EnableException)
        $result.Count | Should -Be 1
        $result[0].Database | Should -BeExactly $TestConfig.AzureSqlDbName
        $result[0].Schema | Should -BeExactly "dbo"
        $piped = @($azureServer.Databases[$TestConfig.AzureSqlDbName] | Get-DbaDbSequence -Sequence $azureSequence -EnableException)
        $piped.Count | Should -Be 1
    }
}

Describe "Native Get-DbaDbSequence over SQL authentication" -Tag IntegrationTests {
    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
            $loginSequence = "dbatoolsci_nseq_" + (Get-Random)
            $null = Invoke-DbaQuery -SqlInstance $loginInstance -SqlCredential $loginCred -Database tempdb -Query "CREATE SEQUENCE dbo.[$loginSequence] AS int;" -EnableException
        }

        AfterAll {
            $null = Invoke-DbaQuery -SqlInstance $loginInstance -SqlCredential $loginCred -Database tempdb -Query "DROP SEQUENCE dbo.[$loginSequence];" -EnableException
        }

        It "works with -SqlCredential" {
            $result = @(Get-DbaDbSequence -SqlInstance $loginInstance -SqlCredential $loginCred -Database tempdb -Sequence $loginSequence -EnableException)
            $result.Count | Should -Be 1
            $result[0].Database | Should -Be "tempdb"
        }

        It "fails cleanly without the credential: a warning and no output" {
            $warnings = $null
            $result = Get-DbaDbSequence -SqlInstance $loginInstance -Database tempdb -WarningVariable warnings -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            ($warnings -join " ") | Should -BeLike "*Failure*"
        }

        # As the pin measured: the connection failure belongs to the nested database gather, which is not given -EnableException.
        It "fails cleanly without the credential under -EnableException, as the pinned function does" {
            $warnings = $null
            $result = Get-DbaDbSequence -SqlInstance $loginInstance -Database tempdb -EnableException -WarningVariable warnings -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            ($warnings -join " ") | Should -BeLike "*Failure*"
        }
    }
}
