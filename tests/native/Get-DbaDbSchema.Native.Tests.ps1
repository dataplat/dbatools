#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaDbSchema",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe "Native Get-DbaDbSchema" -Tag IntegrationTests {
    BeforeAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $instance = $TestConfig.InstanceSingle
        $random = Get-Random
        $server = Connect-DbaInstance -SqlInstance $instance -NonPooledConnection
        $dbA = "dbatoolsci_nsch_a_$random"
        $dbB = "dbatoolsci_nsch_b_$random"
        $dbOff = "dbatoolsci_nsch_off_$random"
        $dbHeld = "dbatoolsci_nsch_held_$random"
        $dbGone = "dbatoolsci_nsch_gone_$random"
        $dbCase = "dbatoolsci_nsch_cs_$random"
        $wildcard = "dbatoolsci_nsch_?_$random"
        foreach ($name in $dbA, $dbB, $dbOff, $dbHeld, $dbGone) {
            $null = $server.Query("CREATE DATABASE [$name];")
        }
        $null = $server.Query("CREATE DATABASE [$dbCase] COLLATE Latin1_General_CS_AS;")
        $null = $server.Query("USE [$dbA]; CREATE USER [own_a] WITHOUT LOGIN; CREATE USER [own_b] WITHOUT LOGIN; EXEC('CREATE SCHEMA [sch_one] AUTHORIZATION [own_a]'); EXEC('CREATE SCHEMA [sch_two] AUTHORIZATION [own_b]'); EXEC('CREATE SCHEMA [sch*star] AUTHORIZATION [own_a]');")
        foreach ($name in $dbB, $dbHeld, $dbGone) {
            $null = $server.Query("USE [$name]; CREATE USER [own_a] WITHOUT LOGIN; EXEC('CREATE SCHEMA [sch_one] AUTHORIZATION [own_a]');")
        }
        $null = $server.Query("USE [$dbCase]; CREATE USER [OwnCase] WITHOUT LOGIN; EXEC('CREATE SCHEMA [SchCase] AUTHORIZATION [OwnCase]'); EXEC('CREATE SCHEMA [schcase]');")
        $null = $server.Query("USE [master]; ALTER DATABASE [$dbOff] SET OFFLINE WITH ROLLBACK IMMEDIATE;")
        $server.Databases.Refresh()
        $objectA = Get-DbaDatabase -SqlInstance $instance -Database $dbA
        $objectB = Get-DbaDatabase -SqlInstance $instance -Database $dbB

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")

        # A record a compiled cmdlet writes or throws carries its implementing type after the id.
        $schemaSuffix = ",Dataplat.Dbatools.Commands.GetDbaDbSchemaCommand"

        # A Pester It runs its body inside a try, so a call outside any try needs a runspace of its own. Returns the rows, whether the next statement ran, the
        # error stream, the warnings, the -ErrorVariable entries and the runspace's own $Error entries (newest first), and the stop, if any.
        function Invoke-NativeOutsideTry {
            param([hashtable]$Arguments, [string]$Script = 'param($Arguments, $Target) Get-DbaDbSchema @Arguments; "next statement"', $Target = $instance)
            $outsideState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $outsideType = (Get-Command Get-DbaDbSchema -CommandType Cmdlet).ImplementingType
            $outsideEntry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList "Get-DbaDbSchema", $outsideType, $null
            $outsideState.Commands.Add($outsideEntry)
            $outsideRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($outsideState)
            $outsideShell = [System.Management.Automation.PowerShell]::Create()
            $outsideOutput = New-Object "System.Management.Automation.PSDataCollection[psobject]"
            $outsideStop = $null
            $splatOutside = $Arguments.Clone()
            $splatOutside["ErrorVariable"] = "schemaErrors"
            try {
                $outsideRunspace.Open()
                $setup = [System.Management.Automation.PowerShell]::Create()
                $setup.Runspace = $outsideRunspace
                $null = $setup.AddScript('$global:schemaErrors = @()').Invoke()
                $setup.Dispose()
                $outsideShell.Runspace = $outsideRunspace
                $null = $outsideShell.AddScript($Script).AddArgument($splatOutside).AddArgument($Target)
                try {
                    $null = $outsideShell.Invoke($null, $outsideOutput)
                } catch {
                    # The stop leaves the runspace's script through Invoke, as a method call's exception.
                    $outsideStop = $PSItem.Exception.InnerException
                }
                $streamErrors = @($outsideShell.Streams.Error)
                $streamWarnings = @($outsideShell.Streams.Warning)
                $reader = [System.Management.Automation.PowerShell]::Create()
                $reader.Runspace = $outsideRunspace
                $variableEntries = @($reader.AddScript('$global:schemaErrors').Invoke())
                $reader.Commands.Clear()
                $historyEntries = @($reader.AddScript('$global:Error').Invoke())
                $reader.Dispose()
                [pscustomobject]@{
                    Rows     = @($outsideOutput | Where-Object { $PSItem.psobject.BaseObject -is [Microsoft.SqlServer.Management.Smo.Schema] })
                    Next     = @($outsideOutput | Where-Object { "$($PSItem.psobject.BaseObject)" -ceq "next statement" }).Count -gt 0
                    Errors   = $streamErrors
                    Warnings = $streamWarnings
                    Variable = @($variableEntries | ForEach-Object { $PSItem.psobject.BaseObject })
                    History  = @($historyEntries | ForEach-Object { $PSItem.psobject.BaseObject })
                    Stop     = $outsideStop
                }
            } finally {
                $outsideShell.Dispose()
                $outsideRunspace.Dispose()
            }
        }

        # The entries a call in this runspace added to the global $Error, newest first: everything in front of the entry that was newest before the call.
        # $Error is shared with Pester, so it is not cleared.
        function Get-NativeErrorHead {
            if ($global:Error.Count -gt 0) { $global:Error[0] }
        }
        function Get-NativeAddedErrors($Head) {
            $added = New-Object System.Collections.ArrayList
            foreach ($entry in $global:Error) {
                if ($null -ne $Head -and [object]::ReferenceEquals($entry, $Head)) { break }
                $null = $added.Add($entry)
            }
            $added.ToArray()
        }

        # The record of a faulting read of $db.Schemas, as the pin's (evidence/pin-schema-20261104.txt, offline-*, held-*, both editions): the engine's
        # ExceptionInGetEnumerator record, an ExtendedTypeSystemException over SMO's ExecutionFailureException over the SqlException, NotSpecified, no target.
        # The id carries the engine's suffix of this cmdlet, and the Activity is this command's name, where the pin's plain record has none
        # (harness-edits.md, "Engine error records in native ports (operator, 2026-11-12)", point 1).
        $enumerateMessage = 'The following exception occurred while trying to enumerate the collection: "An exception occurred while executing a Transact-SQL statement or batch.".'
        function Assert-NativeEnumerationRecord {
            param($Record, [string]$Cause)
            $Record | Should -BeOfType System.Management.Automation.ErrorRecord
            $Record.FullyQualifiedErrorId | Should -BeExactly ("ExceptionInGetEnumerator" + $schemaSuffix)
            $Record.Exception.GetType().FullName | Should -BeExactly "System.Management.Automation.ExtendedTypeSystemException"
            $Record.Exception.Message | Should -BeExactly $enumerateMessage
            $Record.Exception.InnerException.GetType().FullName | Should -BeExactly "Microsoft.SqlServer.Management.Common.ExecutionFailureException"
            $Record.Exception.InnerException.Message | Should -BeExactly "An exception occurred while executing a Transact-SQL statement or batch."
            $Record.Exception.InnerException.InnerException.GetType().Name | Should -BeExactly "SqlException"
            $Record.Exception.InnerException.InnerException.Message | Should -BeExactly $Cause
            "$($Record.CategoryInfo.Category)" | Should -BeExactly "NotSpecified"
            $Record.CategoryInfo.Reason | Should -BeExactly "ExtendedTypeSystemException"
            $Record.CategoryInfo.Activity | Should -BeExactly "Get-DbaDbSchema"
            $Record.TargetObject | Should -BeNullOrEmpty
        }
        $offlineCause = "Database '$dbOff' cannot be opened because it is offline."
        $heldCause = "Database '$dbHeld' is already open and can only have one user at a time."
    }

    AfterAll {
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true
        foreach ($name in $dbA, $dbB, $dbOff, $dbHeld, $dbGone, $dbCase) {
            # This connection's own session may still be in a database a test's USE moved it to, and DROP refuses a database in use.
            $null = $server.Query("USE [master]; IF DB_ID(N'$name') IS NOT NULL BEGIN ALTER DATABASE [$name] SET ONLINE; ALTER DATABASE [$name] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$name]; END;")
        }
        $server.ConnectionContext.Disconnect()
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Output" {
        It "returns the SMO schema with the pinned notes, default view and values" {
            $expected = $server.Query("SELECT s.schema_id, p.name AS owner FROM [$dbA].sys.schemas AS s JOIN [$dbA].sys.database_principals AS p ON p.principal_id = s.principal_id WHERE s.name = N'sch_two';")
            $result = @(Get-DbaDbSchema -SqlInstance $instance -Database $dbA -Schema sch_two)
            $result.Count | Should -Be 1
            $result[0] | Should -BeOfType Microsoft.SqlServer.Management.Smo.Schema
            (@($result[0].PSObject.Properties | Where-Object MemberType -eq "NoteProperty").Name -join ",") | Should -Be "ComputerName,InstanceName,SqlInstance,DatabaseName,DatabaseId"
            ($result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") | Should -Be "ComputerName,InstanceName,SqlInstance,Name,IsSystemObject"
            $result[0].ComputerName | Should -Be $server.ComputerName
            $result[0].InstanceName | Should -Be $server.ServiceName
            $result[0].SqlInstance | Should -Be $server.DomainInstanceName
            $result[0].DatabaseName | Should -Be $dbA
            $result[0].DatabaseId | Should -Be $server.Query("SELECT DB_ID(N'$dbA') AS id;").id
            $result[0].Name | Should -Be "sch_two"
            $result[0].ID | Should -Be $expected.schema_id
            $result[0].Owner | Should -Be $expected.owner
            $result[0].IsSystemObject | Should -BeFalse
            $result[0].Parent.Name | Should -Be $dbA
        }

        It "gives a -SqlInstance schema's Parent the eight notes Get-DbaDatabase gives it, in its order" {
            $parent = @(Get-DbaDbSchema -SqlInstance $instance -Database $dbA -Schema sch_two)[0].Parent
            (@($parent.PSObject.Properties | Where-Object MemberType -eq "NoteProperty").Name -join ",") | Should -Be "BackupStatus,ComputerName,InstanceName,SqlInstance,LastRead,LastWrite,IsCdcEnabled,Size"
            $parent.BackupStatus | Should -BeNullOrEmpty
            $parent.ComputerName | Should -Be $server.ComputerName
            $parent.InstanceName | Should -Be $server.ServiceName
            $parent.SqlInstance | Should -Be $server.DomainInstanceName
            $parent.LastRead | Should -BeNullOrEmpty
            $parent.LastWrite | Should -BeNullOrEmpty
            $parent.IsCdcEnabled | Should -Be ([bool]$server.Query("SELECT is_cdc_enabled FROM sys.databases WHERE name = N'$dbA';").is_cdc_enabled)
            $parent.Size | Should -BeGreaterThan 0
        }

        It "keeps the notes on a second call over the same objects" {
            $first = @($objectA | Get-DbaDbSchema)
            $second = @($objectA | Get-DbaDbSchema)
            $second.Count | Should -Be $first.Count
            (@($second[0].PSObject.Properties | Where-Object MemberType -eq "NoteProperty").Name -join ",") | Should -Be "ComputerName,InstanceName,SqlInstance,DatabaseName,DatabaseId"
        }

        It "reads under -WhatIf and -Confirm, which gate nothing in a read" -Tag "NativeChecklist:whatif-confirm" {
            @(Get-DbaDbSchema -SqlInstance $instance -Database $dbB -WhatIf).Name | Should -Be "sch_one"
            @(Get-DbaDbSchema -SqlInstance $instance -Database $dbB -Confirm:$false).Name | Should -Be "sch_one"
        }
    }

    Context "System schemas and system databases" {
        It "hides system schemas unless asked" -Tag "NativeChecklist:switch-false" {
            @(Get-DbaDbSchema -SqlInstance $instance -Database $dbB).Name | Should -Be "sch_one"
            @(Get-DbaDbSchema -SqlInstance $instance -Database $dbB -IncludeSystemSchemas:$false).Name | Should -Be "sch_one"
            @(Get-DbaDbSchema -SqlInstance $instance -Database $dbB -Schema dbo).Count | Should -Be 0
            @(Get-DbaDbSchema -SqlInstance $instance -Database $dbB -SchemaOwner dbo).Count | Should -Be 0
            @(Get-DbaDbSchema -SqlInstance $instance -Database $dbB -Schema dbo -IncludeSystemSchemas).Name | Should -Be "dbo"
            @(Get-DbaDbSchema -SqlInstance $instance -Database $dbB -SchemaOwner dbo -IncludeSystemSchemas).Name | Should -Be "dbo"
            $names = @(Get-DbaDbSchema -SqlInstance $instance -Database $dbB -IncludeSystemSchemas).Name
            $names | Should -Contain "sch_one"
            $names | Should -Contain "INFORMATION_SCHEMA"
        }

        It "hides system databases of an instance unless asked, also when named" -Tag "NativeChecklist:switch-false" {
            @(Get-DbaDbSchema -SqlInstance $instance -Database master -IncludeSystemSchemas).Count | Should -Be 0
            @(Get-DbaDbSchema -SqlInstance $instance -Database master -IncludeSystemSchemas -IncludeSystemDatabases:$false).Count | Should -Be 0
            @(Get-DbaDbSchema -SqlInstance $instance -Database master -Schema dbo -IncludeSystemSchemas -IncludeSystemDatabases).DatabaseName | Should -Be "master"
        }

        It "reads a piped system database without -IncludeSystemDatabases" {
            @(Get-DbaDbSchema -InputObject $server.Databases["master"] -Schema dbo -IncludeSystemSchemas).DatabaseName | Should -Be "master"
        }

        It "lists databases in the order of sys.databases, not by name" {
            $names = "master", "tempdb", "model", "msdb"
            # The rows of the pin's own Invoke-QueryRawDatabases query, in their order. "SELECT name FROM sys.databases" alone came back by name on 2017 and 2019 (result 20261114T0030154441996Z), where this query's rows come by database_id.
            $expected = @($server.Query("SELECT name, state, SUSER_SNAME(owner_sid) AS [Owner], is_cdc_enabled FROM sys.databases").name | Where-Object { $PSItem -in $names })
            $result = @(Get-DbaDbSchema -SqlInstance $instance -Database $names -Schema dbo -IncludeSystemSchemas -IncludeSystemDatabases)
            ($result.DatabaseName -join ",") | Should -Be ($expected -join ",")
        }
    }

    Context "Selection" {
        It "compares -Schema and -SchemaOwner without regard to case" {
            @(Get-DbaDbSchema -SqlInstance $instance -Database $dbA -Schema SCH_TWO).Name | Should -Be "sch_two"
            @(Get-DbaDbSchema -SqlInstance $instance -Database $dbA -SchemaOwner OWN_B).Name | Should -Be "sch_two"
            @(Get-DbaDbSchema -SqlInstance $instance -Database $dbCase -Schema SCHCASE).Count | Should -Be 2
            @(Get-DbaDbSchema -SqlInstance $instance -Database $dbCase -SchemaOwner owncase).Name | Should -BeExactly "SchCase"
        }

        It "applies -Schema and -SchemaOwner together" {
            @(Get-DbaDbSchema -SqlInstance $instance -Database $dbA -Schema sch_one, sch_two -SchemaOwner own_b).Name | Should -Be "sch_two"
        }

        It "treats -Schema and -SchemaOwner as names, not patterns" {
            @(Get-DbaDbSchema -SqlInstance $instance -Database $dbA -Schema "sch_*").Count | Should -Be 0
            @(Get-DbaDbSchema -SqlInstance $instance -Database $dbA -SchemaOwner "own_*").Count | Should -Be 0
            @(Get-DbaDbSchema -SqlInstance $instance -Database $dbA -Schema "sch*star").Name | Should -Be "sch*star"
        }

        It "reads all for a null filter and none for an empty one, and matches the names beside a null element" {
            @(Get-DbaDbSchema -SqlInstance $instance -Database $dbB -Schema $null).Count | Should -Be 1
            @(Get-DbaDbSchema -SqlInstance $instance -Database $dbB -SchemaOwner $null).Count | Should -Be 1
            @(Get-DbaDbSchema -SqlInstance $instance -Database $dbB -Schema "").Count | Should -Be 0
            @(Get-DbaDbSchema -SqlInstance $instance -Database $dbB -SchemaOwner "").Count | Should -Be 0
            @(Get-DbaDbSchema -SqlInstance $instance -Database $dbB -Schema @()).Count | Should -Be 0
            @(Get-DbaDbSchema -SqlInstance $instance -Database $dbB -SchemaOwner @()).Count | Should -Be 0
            @(Get-DbaDbSchema -SqlInstance $instance -Database $dbB -Schema @($null, "sch_one")).Count | Should -Be 1
            @(Get-DbaDbSchema -SqlInstance $instance -Database $dbB -SchemaOwner @($null, "own_a")).Count | Should -Be 1
        }

        It "leaves piped databases and -InputObject unfiltered by -Database" {
            @($objectA | Get-DbaDbSchema -Database $dbB -Schema sch_one).DatabaseName | Should -Be $dbA
            @(Get-DbaDbSchema -InputObject $objectA -Database $dbB -Schema sch_one).DatabaseName | Should -Be $dbA
        }

        It "compares -Database without regard to case and reads nothing for a database that is not there" {
            @(Get-DbaDbSchema -SqlInstance $instance -Database $dbB.ToUpperInvariant()).DatabaseName | Should -Be $dbB
            @(Get-DbaDbSchema -SqlInstance $instance -Database "dbatoolsci_nsch_none_$random").Count | Should -Be 0
        }

        It "reads every database for a null, an empty string or an empty array -Database, outside any try" {
            # The comma operator keeps @() as one element, so the third value is an empty array.
            foreach ($value in @($null, "", @())) {
                $outside = Invoke-NativeOutsideTry @{ SqlInstance = $instance; Database = $value; Schema = "sch_one" }
                $outside.Stop | Should -BeNullOrEmpty
                $outside.Rows.DatabaseName | Should -Contain $dbA
                $outside.Rows.DatabaseName | Should -Contain $dbB
                $outside.Next | Should -BeTrue
            }
        }

        # Correction database-wildcards.
        It "expands a wildcard in -Database" {
            $names = @(Get-DbaDbSchema -SqlInstance $instance -Database $wildcard -Schema sch_one).DatabaseName | Sort-Object -Unique
            ($names -join ",") | Should -Be (@($dbA, $dbB) -join ",")
        }
    }

    Context "Pipeline input" {
        It "reads each piped database at its record, and one piped twice twice" -Tag "NativeChecklist:pipeline-multiple" {
            ((@($objectA, $objectB | Get-DbaDbSchema -Schema sch_one).DatabaseName) -join ",") | Should -Be (@($dbA, $dbB) -join ",")
            @($objectB, $objectB | Get-DbaDbSchema -Schema sch_one).Count | Should -Be 2
        }

        # Correction named-instance-repeat.
        It "reads a named instance once beside piped databases" {
            ((@($objectA, $objectB | Get-DbaDbSchema -SqlInstance $instance -Database $dbB -Schema sch_one).DatabaseName) -join ",") | Should -Be (@($dbA, $dbB, $dbB) -join ",")
            @($objectB, $objectB, $objectB | Get-DbaDbSchema -SqlInstance $instance -Database $dbB -Schema sch_one).Count | Should -Be 4
        }

        It "reads -InputObject and then each named instance" {
            ((@(Get-DbaDbSchema -InputObject $objectA -SqlInstance $instance, $instance -Database $dbB -Schema sch_one).DatabaseName) -join ",") | Should -Be (@($dbA, $dbB, $dbB) -join ",")
        }

        It "passes over a null element of -InputObject or a piped null with no message" {
            $warnings = $null
            $result = @(Get-DbaDbSchema -InputObject @($null, $objectB) -WarningVariable warnings -WarningAction SilentlyContinue)
            $result.Count | Should -Be 1
            $warnings | Should -BeNullOrEmpty
            @($null, $objectB | Get-DbaDbSchema -WarningVariable warnings -WarningAction SilentlyContinue).Count | Should -Be 1
            $warnings | Should -BeNullOrEmpty
            $record = @($objectB, $null)
            @(, $record | Get-DbaDbSchema -WarningVariable warnings -WarningAction SilentlyContinue).Count | Should -Be 1
            $warnings | Should -BeNullOrEmpty
        }

        It "does nothing for an empty pipeline, also beside a named instance" {
            @(@() | Get-DbaDbSchema -SqlInstance $instance -Database $dbB).Count | Should -Be 0
        }

        It "reads a named instance once for a piped null" {
            @($null | Get-DbaDbSchema -SqlInstance $instance -Database $dbB -Schema sch_one).Count | Should -Be 1
        }

        It "refuses a piped instance through the binder and goes on, -SqlInstance taking no pipeline input" {
            $script = 'param($Arguments, $Target) $Target | Get-DbaDbSchema @Arguments; "next statement"'
            $outside = Invoke-NativeOutsideTry @{ Schema = "sch_one" } -Script $script
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            $outside.Errors[0].FullyQualifiedErrorId | Should -BeExactly ("InputObjectNotBound" + $schemaSuffix)
            $outside.Rows.Count | Should -Be 0
            $outside.Next | Should -BeTrue
        }
    }

    Context "Nothing to read" {
        It "writes nothing for no input, a null or empty -SqlInstance, a null or empty -InputObject, or no input under -EnableException" {
            $nothingForms = @(
                @{ }
                @{ SqlInstance = $null }
                @{ SqlInstance = @() }
                @{ InputObject = $null }
                @{ InputObject = @() }
                @{ EnableException = $true }
            )
            foreach ($arguments in $nothingForms) {
                $outside = Invoke-NativeOutsideTry $arguments
                $outside.Stop | Should -BeNullOrEmpty
                $outside.Rows.Count | Should -Be 0
                $outside.Warnings.Count | Should -Be 0
                $outside.Errors.Count | Should -Be 0
                $outside.Variable.Count | Should -Be 0
                $outside.History.Count | Should -Be 0
                $outside.Next | Should -BeTrue
            }
        }
    }

    Context "The binding fault of the nested Get-DbaDatabase" {
        BeforeAll {
            # The binder record of the pin's nested Get-DbaDatabase for a null element of -SqlInstance (evidence/pin-schema-20261104.txt,
            # instance-null-element-*, both editions). The exception is the public base of the binder's internal type; the id carries this cmdlet's suffix
            # (harness-edits.md, "binder fault records in five ports", point 1, and "Child-command error owner", point 1).
            $bindingNull = "Cannot bind argument to parameter 'SqlInstance' because it is null."
            function Assert-NativeBindingRecord {
                param($Record, [string]$Activity)
                $Record | Should -BeOfType System.Management.Automation.ErrorRecord
                $Record.Exception.GetType().FullName | Should -BeExactly "System.Management.Automation.ParameterBindingException"
                $Record.Exception.Message | Should -BeExactly $bindingNull
                $Record.Exception.InnerException | Should -BeNullOrEmpty
                $Record.FullyQualifiedErrorId | Should -BeExactly ("ParameterArgumentValidationErrorNullNotAllowed" + $schemaSuffix)
                "$($Record.CategoryInfo.Category)" | Should -BeExactly "InvalidData"
                $Record.CategoryInfo.Reason | Should -BeExactly "ParameterBindingValidationException"
                $Record.CategoryInfo.Activity | Should -BeExactly $Activity
                $Record.TargetObject | Should -BeNullOrEmpty
            }
        }

        It 'outside any try, a plain call writes a record for each null element and reads the others, into -ErrorVariable and $Error too' {
            $bindingForms = @(
                @{ SqlInstance = @($null, $instance); Records = 1; Count = 1 }
                @{ SqlInstance = @($instance, $null); Records = 1; Count = 1 }
                @{ SqlInstance = @($null, $null); Records = 2; Count = 0 }
            )
            foreach ($form in $bindingForms) {
                $outside = Invoke-NativeOutsideTry @{ SqlInstance = $form.SqlInstance; Database = $dbB; Schema = "sch_one" }
                $outside.Stop | Should -BeNullOrEmpty
                $outside.Errors.Count | Should -Be $form.Records
                $outside.Variable.Count | Should -Be $form.Records
                $outside.History.Count | Should -Be $form.Records
                foreach ($record in @($outside.Errors) + @($outside.Variable) + @($outside.History)) {
                    Assert-NativeBindingRecord -Record $record -Activity "Get-DbaDatabase"
                }
                for ($n = 0; $n -lt $form.Records; $n++) {
                    [object]::ReferenceEquals($outside.Variable[$n], $outside.History[$form.Records - 1 - $n]) | Should -BeTrue
                }
                $outside.Warnings.Count | Should -Be 0
                $outside.Rows.Count | Should -Be $form.Count
                $outside.Next | Should -BeTrue
            }
        }

        It 'outside any try, keeps the record in -ErrorVariable and $Error without showing it under -ErrorAction SilentlyContinue' {
            $outside = Invoke-NativeOutsideTry @{ SqlInstance = @($null, $instance); Database = $dbB; Schema = "sch_one"; ErrorAction = "SilentlyContinue" }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 0
            $outside.Variable.Count | Should -Be 1
            $outside.History.Count | Should -Be 1
            Assert-NativeBindingRecord -Record $outside.Variable[0] -Activity "Get-DbaDatabase"
            [object]::ReferenceEquals($outside.Variable[0], $outside.History[0]) | Should -BeTrue
            $outside.Rows.Count | Should -Be 1
            $outside.Next | Should -BeTrue
        }

        It "outside any try, the record's -InputObject is still read, first" {
            $outside = Invoke-NativeOutsideTry @{ SqlInstance = @($instance, $null); InputObject = $objectA; Database = $dbB; Schema = "sch_one" }
            $outside.Errors.Count | Should -Be 1
            ($outside.Rows.DatabaseName -join ",") | Should -Be (@($dbA, $dbB) -join ",")
            $outside.Next | Should -BeTrue
        }

        It "outside any try, -EnableException ends the command at the record and the script goes on" -Tag "NativeChecklist:enable-exception" {
            $outside = Invoke-NativeOutsideTry @{ SqlInstance = @($null, $instance); Database = $dbB; EnableException = $true }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            Assert-NativeBindingRecord -Record $outside.Errors[0] -Activity "Get-DbaDatabase"
            $outside.Variable.Count | Should -Be 1
            $outside.Variable[0].GetType().FullName | Should -BeExactly "System.Management.Automation.CmdletInvocationException"
            Assert-NativeBindingRecord -Record $outside.Variable[0].ErrorRecord -Activity "Get-DbaDatabase"
            $outside.History.Count | Should -Be 1
            Assert-NativeBindingRecord -Record $outside.History[0] -Activity "Get-DbaDatabase"
            $outside.Rows.Count | Should -Be 0
            $outside.Next | Should -BeTrue
        }

        It "outside any try, -ErrorAction Stop turns the record into the stop PowerShell gives WriteError" {
            $outside = Invoke-NativeOutsideTry @{ SqlInstance = @($null, $instance); Database = $dbB; ErrorAction = "Stop" }
            $outside.Stop | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
            Assert-NativeBindingRecord -Record $outside.Stop.ErrorRecord -Activity "Get-DbaDbSchema"
            $outside.Variable.Count | Should -Be 1
            $outside.Variable[0].GetType().FullName | Should -BeExactly "System.Management.Automation.ActionPreferenceStopException"
            Assert-NativeBindingRecord -Record $outside.Variable[0].ErrorRecord -Activity "Get-DbaDbSchema"
            $outside.History.Count | Should -Be 2
            $outside.History[0].GetType().FullName | Should -BeExactly "System.Management.Automation.ActionPreferenceStopException"
            Assert-NativeBindingRecord -Record $outside.History[0].ErrorRecord -Activity "Get-DbaDbSchema"
            Assert-NativeBindingRecord -Record $outside.History[1] -Activity "Get-DbaDbSchema"
            $outside.Rows.Count | Should -Be 0
            $outside.Next | Should -BeFalse
        }

        It "inside a caller's try, the catch receives the record and the command does not go on" {
            $failure = $null
            $after = $false
            $errors = @()
            $head = Get-NativeErrorHead
            try {
                $null = Get-DbaDbSchema -SqlInstance @($null, $instance) -InputObject $objectB -ErrorVariable errors
                $after = $true
            } catch {
                $failure = $PSItem
            }
            $added = @(Get-NativeAddedErrors $head)
            Assert-NativeBindingRecord -Record $failure -Activity "Get-DbaDbSchema"
            $after | Should -BeFalse
            @($errors).Count | Should -Be 1
            $errors[0].GetType().FullName | Should -BeExactly "System.Management.Automation.CmdletInvocationException"
            Assert-NativeBindingRecord -Record $errors[0].ErrorRecord -Activity "Get-DbaDbSchema"
            $added.Count | Should -Be 1
            Assert-NativeBindingRecord -Record $added[0] -Activity "Get-DbaDbSchema"
        }

        It "inside a caller's try, -EnableException and -ErrorAction Stop each give the catch the record and end the call" -Tag "NativeChecklist:enable-exception" {
            foreach ($mode in @(@{ EnableException = $true }, @{ ErrorAction = "Stop" })) {
                $failure = $null
                $after = $false
                $errors = @()
                $rows = @()
                $head = Get-NativeErrorHead
                try {
                    $rows = @(Get-DbaDbSchema -SqlInstance @($null, $instance) -Database $dbB -ErrorVariable errors @mode)
                    $after = $true
                } catch {
                    $failure = $PSItem
                }
                $added = @(Get-NativeAddedErrors $head)
                Assert-NativeBindingRecord -Record $failure -Activity "Get-DbaDbSchema"
                $after | Should -BeFalse
                $rows.Count | Should -Be 0
                @($errors).Count | Should -Be 1
                $errors[0].GetType().FullName | Should -BeExactly "System.Management.Automation.CmdletInvocationException"
                Assert-NativeBindingRecord -Record $errors[0].ErrorRecord -Activity "Get-DbaDbSchema"
                $added.Count | Should -Be 1
                Assert-NativeBindingRecord -Record $added[0] -Activity "Get-DbaDbSchema"
            }
        }
    }

    Context "An offline database" {
        It "outside any try, writes the pinned record and reads the next, named or piped" {
            $offObject = $server.Databases[$dbOff]
            $outside = Invoke-NativeOutsideTry @{ InputObject = @($offObject, $objectB) }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            Assert-NativeEnumerationRecord -Record $outside.Errors[0] -Cause $offlineCause
            $outside.Variable.Count | Should -Be 1
            $outside.History.Count | Should -Be 1
            [object]::ReferenceEquals($outside.Variable[0], $outside.History[0]) | Should -BeTrue
            ($outside.Rows.DatabaseName -join ",") | Should -Be $dbB
            $outside.Next | Should -BeTrue

            $outside = Invoke-NativeOutsideTry @{ SqlInstance = $instance; Database = $dbOff }
            $outside.Errors.Count | Should -Be 1
            Assert-NativeEnumerationRecord -Record $outside.Errors[0] -Cause $offlineCause
            $outside.Rows.Count | Should -Be 0
        }

        # Correction stale-schema-list.
        It "writes no row for it after a database that had rows" {
            $offObject = $server.Databases[$dbOff]
            $outside = Invoke-NativeOutsideTry @{ InputObject = @($objectB, $offObject) }
            $outside.Errors.Count | Should -Be 1
            ($outside.Rows.DatabaseName -join ",") | Should -Be $dbB
        }
    }

    Context "A database whose schemas cannot be read" {
        BeforeAll {
            # A separate session holds the database in single-user mode, so reading its schemas faults. Objects read before that are what the command gets.
            $heldReader = Connect-DbaInstance -SqlInstance $instance -NonPooledConnection
            $heldObject = $heldReader.Databases[$dbHeld]
            $heldOther = $heldReader.Databases[$dbB]
            $heldThird = $heldReader.Databases[$dbA]
            $null = $heldObject.IsAccessible
            $null = $heldOther.IsAccessible
            $null = $heldThird.IsAccessible
            $holder = Connect-DbaInstance -SqlInstance $instance -NonPooledConnection
            $null = $holder.ConnectionContext.ExecuteNonQuery("USE [$dbHeld]; ALTER DATABASE [$dbHeld] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;")
            $held = @($heldOther, $heldObject, $heldThird)
        }

        AfterAll {
            $null = $holder.ConnectionContext.ExecuteNonQuery("USE [master]; ALTER DATABASE [$dbHeld] SET MULTI_USER;")
            $holder.ConnectionContext.Disconnect()
            $heldReader.ConnectionContext.Disconnect()
        }

        # Correction stale-schema-list.
        It "outside any try, writes one record, no row for that database, and reads the next, under each filter" {
            foreach ($filters in @{ }, @{ Schema = "sch_one" }, @{ SchemaOwner = "own_a" }, @{ IncludeSystemSchemas = $true }) {
                $outside = Invoke-NativeOutsideTry ($filters + @{ InputObject = $held })
                $outside.Stop | Should -BeNullOrEmpty
                $outside.Errors.Count | Should -Be 1
                Assert-NativeEnumerationRecord -Record $outside.Errors[0] -Cause $heldCause
                $outside.Rows.DatabaseName | Should -Not -Contain $dbHeld
                $outside.Rows.DatabaseName | Should -Contain $dbA
                $outside.Next | Should -BeTrue
            }
        }

        # Correction stale-schema-list.
        It "outside any try, a piped record whose read faults writes no row under its name" {
            $script = 'param($Arguments, $Target) $Target | Get-DbaDbSchema @Arguments; "next statement"'
            $outside = Invoke-NativeOutsideTry @{ } -Script $script -Target $held
            $outside.Errors.Count | Should -Be 1
            $outside.Rows.DatabaseName | Should -Not -Contain $dbHeld
            $outside.Next | Should -BeTrue
        }

        It 'outside any try, a plain call keeps the one record in -ErrorVariable and $Error and reads the next' {
            $outside = Invoke-NativeOutsideTry @{ InputObject = $held; Schema = "sch_one" }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            $outside.Variable.Count | Should -Be 1
            $outside.History.Count | Should -Be 1
            Assert-NativeEnumerationRecord -Record $outside.Errors[0] -Cause $heldCause
            Assert-NativeEnumerationRecord -Record $outside.Variable[0] -Cause $heldCause
            [object]::ReferenceEquals($outside.Variable[0], $outside.History[0]) | Should -BeTrue
            $outside.Rows.DatabaseName | Should -Contain $dbA
            $outside.Next | Should -BeTrue
        }

        It 'outside any try, keeps the record in -ErrorVariable and $Error without showing it under -ErrorAction SilentlyContinue' {
            $outside = Invoke-NativeOutsideTry @{ InputObject = $held; Schema = "sch_one"; ErrorAction = "SilentlyContinue" }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 0
            $outside.Variable.Count | Should -Be 1
            $outside.History.Count | Should -Be 1
            Assert-NativeEnumerationRecord -Record $outside.Variable[0] -Cause $heldCause
            [object]::ReferenceEquals($outside.Variable[0], $outside.History[0]) | Should -BeTrue
            $outside.Rows.DatabaseName | Should -Contain $dbA
            $outside.Next | Should -BeTrue
        }

        It "outside any try, -EnableException ends the command at the record and the script goes on" -Tag "NativeChecklist:enable-exception" {
            $outside = Invoke-NativeOutsideTry @{ InputObject = $held; EnableException = $true }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            Assert-NativeEnumerationRecord -Record $outside.Errors[0] -Cause $heldCause
            $outside.Variable.Count | Should -Be 1
            $outside.Variable[0].GetType().FullName | Should -BeExactly "System.Management.Automation.CmdletInvocationException"
            Assert-NativeEnumerationRecord -Record $outside.Variable[0].ErrorRecord -Cause $heldCause
            $outside.History.Count | Should -Be 1
            Assert-NativeEnumerationRecord -Record $outside.History[0] -Cause $heldCause
            ($outside.Rows.DatabaseName | Select-Object -Unique) | Should -Be $dbB
            $outside.Next | Should -BeTrue
        }

        It "outside any try, -ErrorAction Stop turns the record into the stop PowerShell gives WriteError" {
            $outside = Invoke-NativeOutsideTry @{ InputObject = $held; ErrorAction = "Stop" }
            $outside.Stop | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
            Assert-NativeEnumerationRecord -Record $outside.Stop.ErrorRecord -Cause $heldCause
            $outside.Variable.Count | Should -Be 1
            $outside.Variable[0].GetType().FullName | Should -BeExactly "System.Management.Automation.ActionPreferenceStopException"
            Assert-NativeEnumerationRecord -Record $outside.Variable[0].ErrorRecord -Cause $heldCause
            $outside.History.Count | Should -Be 2
            $outside.History[0].GetType().FullName | Should -BeExactly "System.Management.Automation.ActionPreferenceStopException"
            Assert-NativeEnumerationRecord -Record $outside.History[0].ErrorRecord -Cause $heldCause
            Assert-NativeEnumerationRecord -Record $outside.History[1] -Cause $heldCause
            ($outside.Rows.DatabaseName | Select-Object -Unique) | Should -Be $dbB
            $outside.Next | Should -BeFalse
        }

        It "inside a caller's try, the catch receives the record after the rows before it" {
            $failure = $null
            $after = $false
            $errors = @()
            $rows = New-Object System.Collections.ArrayList
            $head = Get-NativeErrorHead
            try {
                Get-DbaDbSchema -InputObject $held -ErrorVariable errors | ForEach-Object { $null = $rows.Add($PSItem) }
                $after = $true
            } catch {
                $failure = $PSItem
            }
            $added = @(Get-NativeAddedErrors $head)
            Assert-NativeEnumerationRecord -Record $failure -Cause $heldCause
            $after | Should -BeFalse
            ($rows.DatabaseName | Select-Object -Unique) | Should -Be $dbB
            @($errors).Count | Should -Be 1
            $errors[0].GetType().FullName | Should -BeExactly "System.Management.Automation.CmdletInvocationException"
            Assert-NativeEnumerationRecord -Record $errors[0].ErrorRecord -Cause $heldCause
            $added.Count | Should -Be 1
            Assert-NativeEnumerationRecord -Record $added[0] -Cause $heldCause
        }

        It "inside a caller's try, -EnableException and -ErrorAction Stop each give the catch the record and end the call" -Tag "NativeChecklist:enable-exception" {
            foreach ($mode in @(@{ EnableException = $true }, @{ ErrorAction = "Stop" })) {
                $failure = $null
                $after = $false
                $errors = @()
                $rows = New-Object System.Collections.ArrayList
                $head = Get-NativeErrorHead
                try {
                    Get-DbaDbSchema -InputObject $held -ErrorVariable errors @mode | ForEach-Object { $null = $rows.Add($PSItem) }
                    $after = $true
                } catch {
                    $failure = $PSItem
                }
                $added = @(Get-NativeAddedErrors $head)
                Assert-NativeEnumerationRecord -Record $failure -Cause $heldCause
                $after | Should -BeFalse
                ($rows.DatabaseName | Select-Object -Unique) | Should -Be $dbB
                @($errors).Count | Should -Be 1
                $errors[0].GetType().FullName | Should -BeExactly "System.Management.Automation.CmdletInvocationException"
                Assert-NativeEnumerationRecord -Record $errors[0].ErrorRecord -Cause $heldCause
                $added.Count | Should -Be 1
                Assert-NativeEnumerationRecord -Record $added[0] -Cause $heldCause
            }
        }
    }

    Context "A database dropped after its object was read" {
        It "has no rows and no fault, and the database before it does not come back" {
            $goneReader = Connect-DbaInstance -SqlInstance $instance -NonPooledConnection
            $goneObject = $goneReader.Databases[$dbGone]
            $goneOther = $goneReader.Databases[$dbB]
            $null = $goneObject.IsAccessible
            $null = $goneOther.IsAccessible
            $null = $server.Query("USE [master]; ALTER DATABASE [$dbGone] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$dbGone];")
            $outside = Invoke-NativeOutsideTry @{ InputObject = @($goneOther, $goneObject) }
            $goneReader.ConnectionContext.Disconnect()
            $outside.Errors.Count | Should -Be 0
            ($outside.Rows.DatabaseName -join ",") | Should -Be $dbB
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
                    $result = @(Get-DbaDbSchema @splatFailure)
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

Describe "Native Get-DbaDbSchema on Azure SQL Database" -Tag IntegrationTests {
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
        $azureSchema = "dbatoolsci_nsch_" + (Get-Random)
        $null = $azureServer.ConnectionContext.ExecuteNonQuery("EXEC('CREATE SCHEMA [$azureSchema]');")
    }

    AfterAll {
        if ($azureServer) {
            $null = $azureServer.ConnectionContext.ExecuteNonQuery("IF SCHEMA_ID(N'$azureSchema') IS NOT NULL DROP SCHEMA [$azureSchema];")
            $azureServer.ConnectionContext.Disconnect()
        }
    }

    It "reads a schema of an Azure SQL Database through a server object and by pipeline" -Tag "NativeChecklist:azure-sqldb" {
        $azureServer.DatabaseEngineEdition.ToString() | Should -BeExactly "SqlDatabase"
        $result = @(Get-DbaDbSchema -SqlInstance $azureServer -Schema $azureSchema -EnableException)
        $result.Count | Should -Be 1
        $result[0].DatabaseName | Should -BeExactly $TestConfig.AzureSqlDbName
        $piped = @($azureServer.Databases[$TestConfig.AzureSqlDbName] | Get-DbaDbSchema -Schema $azureSchema -EnableException)
        $piped.Count | Should -Be 1
    }
}

Describe "Native Get-DbaDbSchema over SQL authentication" -Tag IntegrationTests {
    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
            $loginRandom = Get-Random
            $loginDatabase = "dbatoolsci_nsch_login_$loginRandom"
            $loginOther = "dbatoolsci_nsch_other_$loginRandom"
            $lowName = "dbatoolsci_nsch_low_$loginRandom"
            $lowPassword = "Nsch-$([guid]::NewGuid().ToString('N'))"
            $lowCred = New-Object System.Management.Automation.PSCredential -ArgumentList $lowName, (ConvertTo-SecureString -String $lowPassword -AsPlainText -Force)
            $loginServer = Connect-DbaInstance -SqlInstance $loginInstance -SqlCredential $loginCred -NonPooledConnection -EnableException
            $null = $loginServer.Query("CREATE DATABASE [$loginDatabase];")
            $null = $loginServer.Query("CREATE DATABASE [$loginOther];")
            $null = $loginServer.Query("USE [master]; CREATE LOGIN [$lowName] WITH PASSWORD = '$lowPassword', CHECK_POLICY = OFF;")
            $null = $loginServer.Query("USE [$loginDatabase]; CREATE USER [own_a] WITHOUT LOGIN; CREATE USER [$lowName] FOR LOGIN [$lowName]; EXEC('CREATE SCHEMA [sch_one] AUTHORIZATION [own_a]'); USE [master];")
        }

        AfterAll {
            [Microsoft.Data.SqlClient.SqlConnection]::ClearAllPools()
            $null = $loginServer.Query("USE [master];")
            foreach ($row in @($loginServer.Query("SELECT session_id FROM sys.dm_exec_sessions WHERE login_name = N'$lowName';") | Where-Object { $null -ne $PSItem })) {
                $null = $loginServer.Query("KILL $($row.session_id);")
            }
            foreach ($name in $loginDatabase, $loginOther) {
                $null = $loginServer.Query("IF DB_ID(N'$name') IS NOT NULL BEGIN ALTER DATABASE [$name] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$name]; END;")
            }
            $null = $loginServer.Query("IF SUSER_ID(N'$lowName') IS NOT NULL DROP LOGIN [$lowName];")
            $loginServer.ConnectionContext.Disconnect()
        }

        It "works with -SqlCredential" {
            $result = @(Get-DbaDbSchema -SqlInstance $loginInstance -SqlCredential $loginCred -Database $loginDatabase -Schema sch_one -EnableException)
            $result.Count | Should -Be 1
            $result[0].DatabaseName | Should -Be $loginDatabase
            $result[0].Owner | Should -Be "own_a"
        }

        It "fails cleanly without the credential: a warning and no output" {
            $warnings = $null
            $result = Get-DbaDbSchema -SqlInstance $loginInstance -Database $loginDatabase -WarningVariable warnings -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            ($warnings -join " ") | Should -BeLike "*Failure*"
        }

        # As the pin measured: the connection failure belongs to the nested database gather, which is not given -EnableException.
        It "fails cleanly without the credential under -EnableException, as the pinned function does" {
            $warnings = $null
            $result = Get-DbaDbSchema -SqlInstance $loginInstance -Database $loginDatabase -EnableException -WarningVariable warnings -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            ($warnings -join " ") | Should -BeLike "*Failure*"
        }

        It "reads a low login's schema with its owner empty, and writes a record for a database it has no user in" {
            $result = @(Get-DbaDbSchema -SqlInstance $loginInstance -SqlCredential $lowCred -Database $loginDatabase -Schema sch_one -EnableException)
            $result.Count | Should -Be 1
            $result[0].Owner | Should -BeNullOrEmpty

            $failure = $null
            try {
                $null = Get-DbaDbSchema -SqlInstance $loginInstance -SqlCredential $lowCred -Database $loginOther
            } catch {
                $failure = $PSItem
            }
            $failure.FullyQualifiedErrorId | Should -BeExactly ("ExceptionInGetEnumerator" + ",Dataplat.Dbatools.Commands.GetDbaDbSchemaCommand")
        }
    }
}
