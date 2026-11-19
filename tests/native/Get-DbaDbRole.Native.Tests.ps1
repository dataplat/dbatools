#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Get-DbaDbRole",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

# NativeChecklist: whatif-confirm N/A -- The pinned command has no SupportsShouldProcess, WhatIf or Confirm parameters; it only reads database roles.

Describe "Native Get-DbaDbRole" -Tag IntegrationTests {
    BeforeAll {
        # Not InstanceSingle: the other edition's leg runs the pinned file there at the same time, and its Its count every database on that
        # instance, so this file's databases (one offline, one held in single-user mode) stay off it.
        $instance = $TestConfig.InstanceMulti1
        $random = Get-Random
        $dbA = "dbatoolsci_nrole_a_$random"
        $dbB = "dbatoolsci_nrole_b_$random"
        $dbOff = "dbatoolsci_nrole_off_$random"
        $dbCase = "dbatoolsci_nrole_cs_$random"
        $dbHeld = "dbatoolsci_nrole_held_$random"
        $dbGone = "dbatoolsci_nrole_gone_$random"
        $dbUnread = "dbatoolsci_nrole_unread_$random"
        $allDatabases = @($dbA, $dbB, $dbOff, $dbCase, $dbHeld, $dbGone, $dbUnread)
        $badInstance = "Data Source=tcp:127.0.0.1,1;Integrated Security=True;Connect Timeout=1;Pooling=False"

        # The fixture's connection is never given to the command.
        $fixture = Connect-DbaInstance -SqlInstance $instance -NonPooledConnection
        # CREATE DATABASE needs an exclusive lock on model, so it fails while another session (the other edition's leg) creates a database
        # there. Try again for up to a minute; a database the failed attempt left is not created twice.
        function New-NativeRoleDatabase {
            param([string]$Name, [string]$Collation)
            $collate = if ($Collation) { " COLLATE $Collation" } else { "" }
            for ($attempt = 1; $attempt -le 20; $attempt++) {
                try {
                    $null = $fixture.Query("IF DB_ID(N'$Name') IS NULL CREATE DATABASE [$Name]$collate;")
                    return
                } catch {
                    if ($attempt -ge 20 -or "$PSItem" -notlike "*exclusive lock on database 'model'*") {
                        throw
                    }
                    Start-Sleep -Seconds 3
                }
            }
        }
        foreach ($name in $dbA, $dbB, $dbOff, $dbHeld, $dbGone, $dbUnread) {
            New-NativeRoleDatabase -Name $name
        }
        New-NativeRoleDatabase -Name $dbCase -Collation "Latin1_General_CS_AS"
        $null = $fixture.Query("USE [$dbA]; CREATE ROLE [role_one]; CREATE ROLE [role_two]; CREATE ROLE [role*star];")
        foreach ($name in $dbB, $dbHeld, $dbGone, $dbUnread) {
            $null = $fixture.Query("USE [$name]; CREATE ROLE [role_one];")
        }
        $null = $fixture.Query("USE [$dbCase]; CREATE ROLE [RoleCase]; CREATE ROLE [rolecase]; CREATE ROLE [PUBLIC];")
        $null = $fixture.Query("USE [master]; ALTER DATABASE [$dbOff] SET OFFLINE WITH ROLLBACK IMMEDIATE;")

        # The objects the tests pass in, with their properties read, from a server of their own.
        $source = Connect-DbaInstance -SqlInstance $instance -NonPooledConnection
        $objectA = $source.Databases[$dbA]
        $objectB = $source.Databases[$dbB]
        $objectOff = $source.Databases[$dbOff]
        $objectHeld = $source.Databases[$dbHeld]
        $objectGone = $source.Databases[$dbGone]
        $objectUnread = $source.Databases[$dbUnread]
        foreach ($object in $objectA, $objectB, $objectOff, $objectHeld, $objectGone) {
            $null = $object.IsAccessible
        }
        $objectUnread.Refresh()

        # A Pester It runs its body inside a try, so a call outside any try needs a runspace of its own.
        function Invoke-NativeOutsideTry {
            param([hashtable]$Arguments, [object[]]$Piped)
            $outsideState = [System.Management.Automation.Runspaces.InitialSessionState]::CreateDefault()
            $outsideType = (Get-Command Get-DbaDbRole -CommandType Cmdlet).ImplementingType
            $outsideEntry = New-Object System.Management.Automation.Runspaces.SessionStateCmdletEntry -ArgumentList "Get-DbaDbRole", $outsideType, $null
            $outsideState.Commands.Add($outsideEntry)
            $outsideRunspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace($outsideState)
            $outsideShell = [System.Management.Automation.PowerShell]::Create()
            $outsideOutput = New-Object "System.Management.Automation.PSDataCollection[psobject]"
            $outsideStop = $null
            try {
                $outsideRunspace.Open()
                $outsideShell.Runspace = $outsideRunspace
                if ($PSBoundParameters.ContainsKey("Piped")) {
                    $null = $outsideShell.AddScript('param($Arguments, $Piped) $Piped | Get-DbaDbRole @Arguments; "next statement"').AddArgument($Arguments).AddArgument($Piped)
                } else {
                    $null = $outsideShell.AddScript('param($Arguments) Get-DbaDbRole @Arguments; "next statement"').AddArgument($Arguments)
                }
                try {
                    $null = $outsideShell.Invoke($null, $outsideOutput)
                } catch {
                    # The stop leaves the runspace's script through Invoke, as a method call's exception.
                    $outsideStop = $PSItem.Exception.InnerException
                }
                [pscustomobject]@{
                    Output   = @($outsideOutput)
                    Rows     = @($outsideOutput | Where-Object { $PSItem -isnot [string] })
                    Errors   = @($outsideShell.Streams.Error)
                    Warnings = @($outsideShell.Streams.Warning)
                    Verbose  = @($outsideShell.Streams.Verbose | Where-Object Message -like "*Getting Database Roles*")
                    Stop     = $outsideStop
                }
            } finally {
                $outsideShell.Dispose()
                $outsideRunspace.Dispose()
            }
        }
    }

    AfterAll {
        try {
            $source.ConnectionContext.Disconnect()
        } catch {
            Write-Warning "Could not disconnect the source server: $PSItem"
        }
        try {
            $null = $fixture.Query("USE [master];")
        } catch {
            Write-Warning "Could not go back to master: $PSItem"
        }
        foreach ($name in $allDatabases) {
            try {
                $null = $fixture.Query("IF DB_ID(N'$name') IS NOT NULL BEGIN ALTER DATABASE [$name] SET ONLINE; ALTER DATABASE [$name] SET SINGLE_USER WITH ROLLBACK IMMEDIATE; DROP DATABASE [$name]; END;")
            } catch {
                Write-Warning "Could not drop ${name}: $PSItem"
            }
        }
        try {
            $fixture.ConnectionContext.Disconnect()
        } catch {
            Write-Warning "Could not disconnect the fixture server: $PSItem"
        }
    }

    Context "Output" {
        It "returns the database's roles as SMO objects in the collection's order, with the pinned notes and default view" {
            $engine = @($fixture.Query("SELECT name FROM [$dbA].sys.database_principals WHERE type = 'R'") | ForEach-Object { $PSItem.name })
            $result = @(Get-DbaDbRole -SqlInstance $instance -Database $dbA -EnableException)

            (($result.Name | Sort-Object) -join ",") | Should -BeExactly (($engine | Sort-Object) -join ",")
            ($result.Name -join ",") | Should -BeExactly (@($objectA.Roles | ForEach-Object { $PSItem.Name }) -join ",")

            $custom = $result | Where-Object Name -eq "role_one"
            $custom | Should -BeOfType Microsoft.SqlServer.Management.Smo.DatabaseRole
            (@($custom.PSObject.Properties | Where-Object MemberType -eq "NoteProperty").Name -join ",") | Should -BeExactly "ComputerName,InstanceName,SqlInstance,Database"
            ($custom.PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames -join ",") | Should -BeExactly "ComputerName,InstanceName,Database,Name,IsFixedRole"
            $custom.ComputerName | Should -Be $fixture.ComputerName
            $custom.InstanceName | Should -Be $fixture.ServiceName
            $custom.SqlInstance | Should -Be $fixture.DomainInstanceName
            $custom.Database | Should -BeExactly $dbA
            $custom.Parent.Name | Should -BeExactly $dbA
            $custom.IsFixedRole | Should -BeFalse
            ($result | Where-Object Name -eq "db_owner").IsFixedRole | Should -BeTrue
        }

        It "replaces what an earlier decoration left on the object" {
            $first = @(Get-DbaDbRole -InputObject $objectB -Role "role_one")[0]
            Add-Member -Force -InputObject $first -MemberType NoteProperty -Name Database -Value "stale"
            Add-Member -Force -InputObject $first -MemberType NoteProperty -Name ComputerName -Value "stale"

            $second = @(Get-DbaDbRole -InputObject $objectB -Role "role_one")[0]
            $second.Database | Should -BeExactly $dbB
            $second.ComputerName | Should -Be $fixture.ComputerName
            @($second.PSObject.Properties | Where-Object MemberType -eq "NoteProperty").Count | Should -Be 4
        }
    }

    Context "Selection" {
        It "matches -Database, -ExcludeDatabase, -Role and -ExcludeRole in any case" {
            @(Get-DbaDbRole -SqlInstance $instance -Database $dbB.ToUpperInvariant() -Role "ROLE_ONE").Database | Should -BeExactly $dbB
            @(Get-DbaDbRole -SqlInstance $instance -Database $dbA, $dbB -ExcludeDatabase $dbB.ToUpperInvariant() -Role "role_one").Database | Should -BeExactly $dbA
            $kept = @(Get-DbaDbRole -SqlInstance $instance -Database $dbB -ExcludeRole "ROLE_ONE", "DB_OWNER")
            $kept.Count | Should -Be 9
            $kept.Name | Should -Not -Contain "role_one"
            $kept.Name | Should -Not -Contain "db_owner"
        }

        It "treats a null, an empty array and one empty string as no filter, and two empty strings as filters" {
            foreach ($none in @{ Role = $null }, @{ Role = @() }, @{ Role = "" }, @{ ExcludeRole = $null }, @{ ExcludeRole = @() }, @{ ExcludeRole = "" }) {
                @(Get-DbaDbRole -SqlInstance $instance -Database $dbB @none).Count | Should -Be 11
            }
            @(Get-DbaDbRole -SqlInstance $instance -Database $dbB -Role "", "").Count | Should -Be 0
            @(Get-DbaDbRole -SqlInstance $instance -Database $dbB -ExcludeRole "", "").Count | Should -Be 11
            @(Get-DbaDbRole -SqlInstance $instance -Database $dbB -Role $null, "role_one").Name | Should -BeExactly "role_one"
            (@(Get-DbaDbRole -SqlInstance $instance -Database "" -Role "role_one").Database | Sort-Object) | Should -Contain $dbB
        }

        It "reads a database object bound to -Database as its bracketed text, so it matches nothing" {
            @(Get-DbaDbRole -SqlInstance $instance -Database $objectB -Role "role_one").Count | Should -Be 0
        }

        It "excludes the fixed roles and public only when -ExcludeFixedRole is on" -Tag "NativeChecklist:switch-false" {
            (@(Get-DbaDbRole -SqlInstance $instance -Database $dbA -ExcludeFixedRole).Name | Sort-Object) -join "," | Should -BeExactly (@("role*star", "role_one", "role_two" | Sort-Object) -join ",")
            @(Get-DbaDbRole -SqlInstance $instance -Database $dbB -ExcludeFixedRole:$false).Count | Should -Be 11
        }

        It "applies -Role, -ExcludeRole and -ExcludeFixedRole together" {
            @(Get-DbaDbRole -SqlInstance $instance -Database $dbA -Role "role_one", "role_two" -ExcludeRole "role_two").Name | Should -BeExactly "role_one"
            @(Get-DbaDbRole -SqlInstance $instance -Database $dbA -Role "db_owner", "public", "role_one" -ExcludeFixedRole).Name | Should -BeExactly "role_one"
        }

        # Watchman b6abd0c975fb1beb: -Database and -ExcludeDatabase select only databases read from -SqlInstance; this is the pinned contract.
        It "leaves piped databases unfiltered by -Database and -ExcludeDatabase" {
            @($objectA | Get-DbaDbRole -Database $dbB -Role "role_one").Database | Should -BeExactly $dbA
            @($objectA | Get-DbaDbRole -ExcludeDatabase $dbA -Role "role_one").Database | Should -BeExactly $dbA
        }

        It "skips an inaccessible database without a word on both paths" {
            $named = @(Get-DbaDbRole -SqlInstance $instance -Database $dbOff -Verbose -WarningVariable warnings -WarningAction SilentlyContinue 4>&1)
            @($named | Where-Object { "$PSItem" -like "*Getting Database Roles*" }).Count | Should -Be 0
            @($named | Where-Object { $PSItem -isnot [System.Management.Automation.VerboseRecord] }).Count | Should -Be 0
            $warnings | Should -BeNullOrEmpty

            $piped = @($objectOff, $objectB | Get-DbaDbRole -Role "role_one" -Verbose -WarningVariable warnings -WarningAction SilentlyContinue 4>&1)
            @($piped | Where-Object { "$PSItem" -like "*Getting Database Roles*" }).Count | Should -Be 1
            @($piped | Where-Object { "$PSItem".Contains("Getting Database Roles for [$dbB] on [") }).Count | Should -Be 1
            @($piped | Where-Object { $PSItem -isnot [System.Management.Automation.VerboseRecord] }).Database | Should -BeExactly $dbB
            $warnings | Should -BeNullOrEmpty
        }

        It "says it is reading a null element of -InputObject and goes on" {
            $messages = @(Get-DbaDbRole -InputObject @($null, $objectB) -Role "role_one" -Verbose -WarningVariable warnings -WarningAction SilentlyContinue 4>&1)
            @($messages | Where-Object { "$PSItem" -like "*Getting Database Roles for  on*" }).Count | Should -Be 1
            @($messages | Where-Object { $PSItem -isnot [System.Management.Automation.VerboseRecord] }).Database | Should -BeExactly $dbB
            $warnings | Should -BeNullOrEmpty
        }

        It "warns when no form of input has a value, and stops there under -EnableException" -Tag "NativeChecklist:enable-exception", "NativeChecklist:switch-false" {
            foreach ($form in @{ }, @{ InputObject = $null }, @{ InputObject = @() }, @{ SqlInstance = $null }, @{ SqlInstance = @() }) {
                @(Get-DbaDbRole @form -EnableException:$false -WarningVariable warnings -WarningAction SilentlyContinue).Count | Should -Be 0
                ($warnings -join " ") | Should -BeLike "*You must pipe in a database or specify a SqlInstance*"
                { Get-DbaDbRole @form -EnableException -WarningAction SilentlyContinue } | Should -Throw -ExpectedMessage "*You must pipe in a database or specify a SqlInstance*" -ErrorId "dbatools_Get-DbaDbRole*"
            }
        }
    }

    Context "Pipeline input" {
        It "returns the roles of each piped instance once" -Tag "NativeChecklist:pipeline-multiple" {
            @($instance, $instance | Get-DbaDbRole -Database $dbB -Role "role_one").Count | Should -Be 2
            @($instance, $instance, $instance | Get-DbaDbRole -Database $dbB -Role "role_one").Count | Should -Be 3
        }

        It "reads a named -SqlInstance once beside piped databases" {
            (@($objectA, $objectB | Get-DbaDbRole -SqlInstance $instance -Database $dbB -Role "role_one").Database -join ",") | Should -BeExactly "$dbA,$dbB,$dbB"
            (@($null, $null | Get-DbaDbRole -SqlInstance $instance -Database $dbB -Role "role_one").Database -join ",") | Should -BeExactly $dbB
        }

        It "reads each record's own input, whatever came before it" {
            (@($objectA, $objectB | Get-DbaDbRole -Role "role_one").Database -join ",") | Should -BeExactly "$dbA,$dbB"
            (@($instance, $objectA | Get-DbaDbRole -Database $dbB -Role "role_one").Database -join ",") | Should -BeExactly "$dbB,$dbA"
            (@($objectA, $instance | Get-DbaDbRole -Database $dbB -Role "role_one").Database -join ",") | Should -BeExactly "$dbA,$dbB"
            (@($instance, $objectA, $instance | Get-DbaDbRole -Database $dbB -Role "role_one").Database -join ",") | Should -BeExactly "$dbB,$dbA,$dbB"
        }

        It "reads -InputObject before a -SqlInstance named beside it" {
            (@(Get-DbaDbRole -SqlInstance $instance -Database $dbB -InputObject $objectA -Role "role_one").Database -join ",") | Should -BeExactly "$dbA,$dbB"
        }

        It "warns at a null record and goes on, and reads nothing from an empty pipeline" {
            @($null | Get-DbaDbRole -WarningVariable warnings -WarningAction SilentlyContinue).Count | Should -Be 0
            ($warnings -join " ") | Should -BeLike "*You must pipe in a database or specify a SqlInstance*"
            @($null, $objectB | Get-DbaDbRole -Role "role_one" -WarningVariable warnings -WarningAction SilentlyContinue).Database | Should -BeExactly $dbB
            ($warnings -join " ") | Should -BeLike "*You must pipe in a database or specify a SqlInstance*"
            @($null, $instance | Get-DbaDbRole -Database $dbB -Role "role_one" -WarningVariable warnings -WarningAction SilentlyContinue).Database | Should -BeExactly $dbB
            ($warnings -join " ") | Should -BeLike "*You must pipe in a database or specify a SqlInstance*"
            @($null | Get-DbaDbRole -SqlInstance $instance -Database $dbB -Role "role_one" -WarningVariable warnings -WarningAction SilentlyContinue).Database | Should -BeExactly $dbB
            $warnings | Should -BeNullOrEmpty
            @(@() | Get-DbaDbRole -SqlInstance $instance -Database $dbB -WarningVariable warnings -WarningAction SilentlyContinue).Count | Should -Be 0
            $warnings | Should -BeNullOrEmpty
        }
    }

    Context "Documented wildcards" {
        It "expands a wildcard in -Database" {
            (@(Get-DbaDbRole -SqlInstance $instance -Database "dbatoolsci_nrole_?_$random" -Role "role_one").Database -join ",") | Should -BeExactly "$dbA,$dbB"
        }

        It "expands a wildcard in -ExcludeDatabase" {
            @(Get-DbaDbRole -SqlInstance $instance -Database $dbA, $dbB -ExcludeDatabase "dbatoolsci_nrole_b*" -Role "role_one").Database | Should -BeExactly $dbA
        }

        It "expands a wildcard in -Role" {
            (@(Get-DbaDbRole -SqlInstance $instance -Database $dbB, $dbA -Role "ROLE_T*").Name -join ",") | Should -BeExactly "role_two"
            @(Get-DbaDbRole -InputObject $objectA -Role "role_?wo").Name | Should -BeExactly "role_two"
        }

        It "expands a wildcard in -ExcludeRole" {
            (@(Get-DbaDbRole -SqlInstance $instance -Database $dbB -ExcludeRole "db_*").Name -join ",") | Should -BeExactly "public,role_one"
            @(Get-DbaDbRole -InputObject $objectB -ExcludeRole "db_*", "publi?").Name | Should -BeExactly "role_one"
        }

        It "keeps a real name holding a wildcard character literal, and brackets and invalid patterns literal" {
            @(Get-DbaDbRole -SqlInstance $instance -Database $dbA -Role "role*star").Name | Should -BeExactly "role*star"
            @(Get-DbaDbRole -SqlInstance $instance -Database $dbA -ExcludeRole "role*star" -ExcludeFixedRole).Count | Should -Be 2
            @(Get-DbaDbRole -SqlInstance $instance -Database $dbA -Role "role_[o]ne").Count | Should -Be 0
            @(Get-DbaDbRole -SqlInstance $instance -Database $dbA -Role "role_[*").Count | Should -Be 0
        }
    }

    Context "A case-sensitive database" {
        It "matches names in any case and returns both spellings" {
            (@(Get-DbaDbRole -SqlInstance $instance -Database $dbCase -Role "ROLECASE").Name | Sort-Object -CaseSensitive -Unique).Count | Should -Be 2
        }

        It "keeps a custom role named PUBLIC under -ExcludeFixedRole" {
            $kept = @(Get-DbaDbRole -SqlInstance $instance -Database $dbCase -ExcludeFixedRole)
            $kept.Count | Should -Be 3
            $kept.Name -ccontains "PUBLIC" | Should -BeTrue
            $kept.Name -ccontains "public" | Should -BeFalse
        }
    }

    Context "A failed instance" {
        It "warns and reads the other instances without -EnableException" -Tag "NativeChecklist:multi-instance-failure", "NativeChecklist:switch-false" {
            $splatFailure = @{
                SqlInstance     = @($instance, $badInstance, $instance)
                Database        = $dbB
                Role            = "role_one"
                EnableException = $false
                WarningVariable = "failureWarnings"
                WarningAction   = "SilentlyContinue"
            }
            (@(Get-DbaDbRole @splatFailure).Database -join ",") | Should -BeExactly "$dbB,$dbB"
            ($failureWarnings -join " ") | Should -BeLike "*Failure*"
            $recorded = $global:Error | Where-Object FullyQualifiedErrorId -like "dbatools_Get-DbaDatabase*" | Select-Object -First 1
            "$($recorded.CategoryInfo.Category)" | Should -BeExactly "ConnectionError"
        }

        It "stops before any role under -EnableException, which the pin gives Get-DbaDatabase" -Tag "NativeChecklist:multi-instance-failure", "NativeChecklist:enable-exception" {
            $streamed = New-Object System.Collections.ArrayList
            $failure = $null
            try {
                Get-DbaDbRole -SqlInstance @($instance, $badInstance, $instance) -Database $dbB -Role "role_one" -EnableException -WarningAction SilentlyContinue | ForEach-Object { $null = $streamed.Add($PSItem) }
            } catch {
                $failure = $PSItem
            }
            $failure | Should -Not -BeNullOrEmpty
            $failure.FullyQualifiedErrorId | Should -BeLike "dbatools_Get-DbaDatabase*"
            "$($failure.CategoryInfo.Category)" | Should -BeExactly "ConnectionError"
            $failure.TargetObject | Should -BeOfType [string]
            $failure.TargetObject | Should -BeLike "*127.0.0.1,1"
            $failure.Exception.GetType().FullName | Should -BeExactly "System.Exception"
            $failure.Exception.InnerException | Should -Not -BeNullOrEmpty
            $streamed.Count | Should -Be 0
        }
    }

    Context "A role read that faults" {
        BeforeAll {
            # Another session takes the database from inside it. The object read its properties before, so it still says accessible, and its roles
            # are not loaded until the command reads them: these tests never read them.
            $holder = Connect-DbaInstance -SqlInstance $instance -NonPooledConnection
            $holder.ConnectionContext.ExecuteNonQuery("USE [$dbHeld]; ALTER DATABASE [$dbHeld] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;")
            $held = @($objectHeld, $objectB)
            $enumerationMessage = 'The following exception occurred while trying to enumerate the collection: "An exception occurred while executing a Transact-SQL statement or batch.".'
            $openMessage = "Database '$dbHeld' is already open and can only have one user at a time."

            # As the pin measured on both editions: evidence/pin-role2-20261102.txt, single-user-object.
            function Assert-RoleFault {
                param($Record)
                $Record.Exception | Should -BeOfType System.Management.Automation.ExtendedTypeSystemException
                $Record.Exception.Message | Should -BeExactly $enumerationMessage
                $Record.Exception.InnerException | Should -BeOfType Microsoft.SqlServer.Management.Common.ExecutionFailureException
                $Record.Exception.InnerException.InnerException.Message | Should -BeExactly $openMessage
                $Record.FullyQualifiedErrorId | Should -BeLike "ExceptionInGetEnumerator,*"
                "$($Record.CategoryInfo.Category)" | Should -BeExactly "NotSpecified"
                $Record.CategoryInfo.Reason | Should -BeExactly "ExtendedTypeSystemException"
                $Record.TargetObject | Should -BeNullOrEmpty
            }
        }

        AfterAll {
            try {
                $holder.ConnectionContext.ExecuteNonQuery("USE [master]; ALTER DATABASE [$dbHeld] SET MULTI_USER;")
            } catch {
                Write-Warning "Could not release ${dbHeld}: $PSItem"
            }
            try {
                $holder.ConnectionContext.Disconnect()
            } catch {
                Write-Warning "Could not disconnect the holder: $PSItem"
            }
        }

        It "outside any try, a plain call writes the record and goes on to the next database" {
            $outside = Invoke-NativeOutsideTry -Arguments @{ InputObject = $held; Verbose = $true }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            Assert-RoleFault -Record $outside.Errors[0]
            $outside.Warnings.Count | Should -Be 0
            $outside.Rows.Count | Should -Be 11
            @($outside.Rows.Database | Select-Object -Unique) | Should -BeExactly $dbB
            $outside.Output[-1] | Should -BeExactly "next statement"
            $outside.Verbose.Count | Should -Be 2
        }

        It "outside any try, a plain call writes the record once for each active filter and once for the read" {
            foreach ($form in @(
                    @{ Filters = @{ Role = "role_one" }; Faults = 2 }
                    @{ Filters = @{ ExcludeRole = "db_*" }; Faults = 2 }
                    @{ Filters = @{ ExcludeFixedRole = $true }; Faults = 2 }
                    @{ Filters = @{ Role = "role_one"; ExcludeRole = "x" }; Faults = 3 }
                    @{ Filters = @{ Role = "role_one"; ExcludeRole = "x"; ExcludeFixedRole = $true }; Faults = 4 }
                )) {
                $outside = Invoke-NativeOutsideTry -Arguments ($form.Filters + @{ InputObject = $held })
                $outside.Stop | Should -BeNullOrEmpty
                $outside.Errors.Count | Should -Be $form.Faults
                foreach ($record in $outside.Errors) {
                    Assert-RoleFault -Record $record
                }
                # Each enumeration's fault is a record of its own, as in the pin; never the same record written again.
                for ($i = 1; $i -lt $outside.Errors.Count; $i++) {
                    [object]::ReferenceEquals($outside.Errors[$i], $outside.Errors[$i - 1]) | Should -BeFalse
                }
                @($outside.Rows.Database | Select-Object -Unique) | Should -BeExactly $dbB
                $outside.Output[-1] | Should -BeExactly "next statement"
            }
        }

        It "outside any try, a plain call goes on along a pipeline too" {
            $outside = Invoke-NativeOutsideTry -Arguments @{ Role = "role_one" } -Piped $held
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 2
            @($outside.Rows.Database) | Should -BeExactly $dbB
            $outside.Output[-1] | Should -BeExactly "next statement"
        }

        It "outside any try, -EnableException ends the command at the fault and the script goes on" -Tag "NativeChecklist:enable-exception" {
            $outside = Invoke-NativeOutsideTry -Arguments @{ InputObject = $held; EnableException = $true }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            Assert-RoleFault -Record $outside.Errors[0]
            $outside.Rows.Count | Should -Be 0
            ($outside.Output -join ",") | Should -BeExactly "next statement"
        }

        It "outside any try, -ErrorAction Stop turns the fault into the stop PowerShell gives WriteError" {
            $outside = Invoke-NativeOutsideTry -Arguments @{ InputObject = $held; ErrorAction = "Stop" }
            $outside.Stop | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
            Assert-RoleFault -Record $outside.Stop.ErrorRecord
            $outside.Output.Count | Should -Be 0
        }

        It "inside a caller's try, the catch receives the record and the command does not go on" {
            $streamed = New-Object System.Collections.ArrayList
            $failure = $null
            $after = $false
            try {
                Get-DbaDbRole -InputObject $held | ForEach-Object { $null = $streamed.Add($PSItem) }
                $after = $true
            } catch {
                $failure = $PSItem
            }
            $failure | Should -Not -BeNullOrEmpty
            Assert-RoleFault -Record $failure
            $after | Should -BeFalse
            $streamed.Count | Should -Be 0
        }

        It "skips the held database without a fault when a fresh read says it is not accessible" {
            $splatFresh = @{
                SqlInstance     = $instance
                Database        = $dbHeld, $dbB
                Role            = "role_one"
                WarningVariable = "freshWarnings"
                WarningAction   = "SilentlyContinue"
            }
            @(Get-DbaDbRole @splatFresh).Database | Should -BeExactly $dbB
            $freshWarnings | Should -BeNullOrEmpty
        }
    }

    Context "A database dropped after its object was read" {
        BeforeAll {
            $null = $fixture.Query("USE [master]; DROP DATABASE [$dbGone]; DROP DATABASE [$dbUnread];")
        }

        # As the pin measured on both editions: evidence/pin-role2-20261102.txt, gone-plain and unread-plain.
        It "reads no roles and no fault, whether or not its properties were read, and goes on" {
            foreach ($object in $objectGone, $objectUnread) {
                $outside = Invoke-NativeOutsideTry -Arguments @{ InputObject = @($object, $objectB); Role = "role_one"; Verbose = $true }
                $outside.Stop | Should -BeNullOrEmpty
                $outside.Errors.Count | Should -Be 0
                @($outside.Rows.Database) | Should -BeExactly $dbB
                $outside.Verbose.Count | Should -Be 2
            }
        }
    }

    Context "A null element in -SqlInstance" {
        BeforeAll {
            $bindingMessage = "Cannot bind argument to parameter 'SqlInstance' because it is null."

            # As the pin measured on both editions: evidence/pin-role-20261102.txt, instance-null-element-*. The binder's own type is internal, so the port
            # carries its public base, and the engine names the compiled command in the id. The activity follows the pin's id suffix: the nested
            # Get-DbaDatabase outside any try without -ErrorAction Stop, this command under a caller's try or that switch.
            function Assert-BindingFault {
                param($Record, [string]$Activity = "Get-DbaDatabase")
                $Record.Exception | Should -BeOfType System.Management.Automation.ParameterBindingException
                $Record.Exception.Message | Should -BeExactly $bindingMessage
                $Record.FullyQualifiedErrorId | Should -BeLike "ParameterArgumentValidationErrorNullNotAllowed,*"
                "$($Record.CategoryInfo.Category)" | Should -BeExactly "InvalidData"
                $Record.CategoryInfo.Reason | Should -BeExactly "ParameterBindingValidationException"
                $Record.CategoryInfo.Activity | Should -BeExactly $Activity
                $Record.TargetObject | Should -BeNullOrEmpty
            }
        }

        It "outside any try, a plain call writes the record, reads no instance of that array, and goes on" {
            foreach ($form in @(, @($null, $instance)), @(, @($instance, $null)), @(, @($null, $null))) {
                $outside = Invoke-NativeOutsideTry -Arguments @{ SqlInstance = $form[0]; Database = $dbB; Role = "role_one" }
                $outside.Stop | Should -BeNullOrEmpty
                $outside.Errors.Count | Should -Be 1
                Assert-BindingFault -Record $outside.Errors[0]
                $outside.Rows.Count | Should -Be 0
                ($outside.Output -join ",") | Should -BeExactly "next statement"
            }
        }

        It "outside any try, a plain call goes on to the databases given beside the array" {
            $outside = Invoke-NativeOutsideTry -Arguments @{ SqlInstance = @($instance, $null); InputObject = $objectA; Database = $dbB; Role = "role_one" }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            Assert-BindingFault -Record $outside.Errors[0]
            @($outside.Rows.Database) | Should -BeExactly $dbA
        }

        # As the pin measured on both editions: evidence/pin-role3-20261102.txt, array-alone, array-first and array-after-database.
        It "outside any try, a piped array holding a null writes the record and reads the other records" {
            $record = @($instance, $null)
            foreach ($form in @(
                    @{ Piped = @(, $record); Databases = "" }
                    @{ Piped = @($record, $instance); Databases = $dbB }
                    @{ Piped = @($objectB, $record); Databases = $dbB }
                )) {
                $outside = Invoke-NativeOutsideTry -Arguments @{ Database = $dbB; Role = "role_one" } -Piped $form.Piped
                $outside.Stop | Should -BeNullOrEmpty
                $outside.Errors.Count | Should -Be 1
                Assert-BindingFault -Record $outside.Errors[0]
                (@($outside.Rows.Database) -join ",") | Should -BeExactly $form.Databases
                $outside.Output[-1] | Should -BeExactly "next statement"
            }
        }

        # The pin gives four rows here (evidence/pin-role3-20261102.txt, array-between), by the repeat of correction piped-instance-repeat.
        It "outside any try, a piped array holding a null between instances returns each other instance once" {
            $record = @($instance, $null)
            $outside = Invoke-NativeOutsideTry -Arguments @{ Database = $dbB; Role = "role_one" } -Piped @($instance, $record, $instance)
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            Assert-BindingFault -Record $outside.Errors[0]
            (@($outside.Rows.Database) -join ",") | Should -BeExactly "$dbB,$dbB"
        }

        It "outside any try, -EnableException ends the command at the fault and the script goes on" -Tag "NativeChecklist:enable-exception" {
            $outside = Invoke-NativeOutsideTry -Arguments @{ SqlInstance = @($instance, $null); InputObject = $objectA; Database = $dbB; Role = "role_one"; EnableException = $true }
            $outside.Stop | Should -BeNullOrEmpty
            $outside.Errors.Count | Should -Be 1
            Assert-BindingFault -Record $outside.Errors[0]
            ($outside.Output -join ",") | Should -BeExactly "next statement"
        }

        It "outside any try, -ErrorAction Stop turns the fault into the stop PowerShell gives WriteError" {
            $outside = Invoke-NativeOutsideTry -Arguments @{ SqlInstance = @($instance, $null); InputObject = $objectA; Database = $dbB; Role = "role_one"; ErrorAction = "Stop" }
            $outside.Stop | Should -BeOfType System.Management.Automation.ActionPreferenceStopException
            Assert-BindingFault -Record $outside.Stop.ErrorRecord -Activity "Get-DbaDbRole"
            $outside.Output.Count | Should -Be 0
        }

        It "inside a caller's try, the catch receives the record and the command does not go on" {
            $streamed = New-Object System.Collections.ArrayList
            $failure = $null
            $after = $false
            try {
                Get-DbaDbRole -SqlInstance @($instance, $null) -InputObject $objectA -Database $dbB -Role "role_one" | ForEach-Object { $null = $streamed.Add($PSItem) }
                $after = $true
            } catch {
                $failure = $PSItem
            }
            $failure | Should -Not -BeNullOrEmpty
            Assert-BindingFault -Record $failure -Activity "Get-DbaDbRole"
            $after | Should -BeFalse
            $streamed.Count | Should -Be 0
        }

        It "inside a caller's try, -EnableException and -ErrorAction Stop each give the catch the record and end the call" {
            foreach ($option in @(@{ EnableException = $true }, @{ ErrorAction = "Stop" })) {
                $splatFault = @{ SqlInstance = @($instance, $null); InputObject = $objectA; Database = $dbB; Role = "role_one" } + $option
                $streamed = New-Object System.Collections.ArrayList
                $failure = $null
                $after = $false
                try {
                    Get-DbaDbRole @splatFault | ForEach-Object { $null = $streamed.Add($PSItem) }
                    $after = $true
                } catch {
                    $failure = $PSItem
                }
                $failure | Should -Not -BeNullOrEmpty
                Assert-BindingFault -Record $failure -Activity "Get-DbaDbRole"
                $after | Should -BeFalse
                $streamed.Count | Should -Be 0
            }
        }
    }
}

Describe "Native Get-DbaDbRole on Azure SQL Database" -Tag IntegrationTests {
    It "reads the roles of an Azure SQL Database by -SqlInstance and by pipeline" -Tag "NativeChecklist:azure-sqldb" {
        $splatAzureConnection = @{
            SqlInstance   = $TestConfig.AzureSqlDbServer
            Database      = $TestConfig.AzureSqlDbName
            SqlCredential = $TestConfig.AzureSqlDbCred
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
        $azureExpected = @($azureServer.ConnectionContext.ExecuteWithResults("SELECT name FROM sys.database_principals WHERE type = 'R';").Tables[0].Rows | ForEach-Object { $PSItem.name })
        $azureCustom = @($azureServer.ConnectionContext.ExecuteWithResults("SELECT name FROM sys.database_principals WHERE type = 'R' AND is_fixed_role = 0 AND name <> N'public';").Tables[0].Rows | ForEach-Object { $PSItem.name })
        $splatAzureRole = @{
            SqlInstance     = $azureServer
            Database        = $TestConfig.AzureSqlDbName
            EnableException = $true
        }
        $azureRows = @(Get-DbaDbRole @splatAzureRole)
        (($azureRows.Name | Sort-Object) -join ",") | Should -BeExactly (($azureExpected | Sort-Object) -join ",")
        @($azureRows.Database | Select-Object -Unique) | Should -BeExactly $TestConfig.AzureSqlDbName
        $azureRows[0].SqlInstance | Should -Be $azureServer.DomainInstanceName
        ($azureRows | Where-Object Name -eq "db_owner").IsFixedRole | Should -BeTrue

        @(Get-DbaDbRole @splatAzureRole -Role "db_owner").Name | Should -BeExactly "db_owner"
        (@(Get-DbaDbRole @splatAzureRole -ExcludeFixedRole).Name | Sort-Object) -join "," | Should -BeExactly (($azureCustom | Sort-Object) -join ",")

        $azurePiped = @($azureServer.Databases[$TestConfig.AzureSqlDbName] | Get-DbaDbRole -EnableException)
        (($azurePiped.Name | Sort-Object) -join ",") | Should -BeExactly (($azureExpected | Sort-Object) -join ",")

        # The database has just answered, so the connection this command opens itself needs no retry.
        $splatAzureLogin = @{
            SqlInstance     = $TestConfig.AzureSqlDbServer
            SqlCredential   = $TestConfig.AzureSqlDbCred
            Database        = $TestConfig.AzureSqlDbName
            Role            = "db_owner"
            EnableException = $true
        }
        @(Get-DbaDbRole @splatAzureLogin).Database | Should -BeExactly $TestConfig.AzureSqlDbName
    }
}

Describe "Native Get-DbaDbRole over SQL authentication" -Tag IntegrationTests {
    Context "SQL login" -Tag NativeChecklist:sql-login {
        BeforeAll {
            $loginInstance = $TestConfig.InstanceSqlLogin
            $loginCred = $TestConfig.SqlLoginCred
        }

        It "works with -SqlCredential" {
            $splatLoginRole = @{
                SqlInstance     = $loginInstance
                SqlCredential   = $loginCred
                Database        = "master"
                Role            = "db_owner"
                EnableException = $true
            }
            $loginRows = @(Get-DbaDbRole @splatLoginRole)
            $loginRows.Count | Should -Be 1
            $loginRows[0].Name | Should -BeExactly "db_owner"
            $loginRows[0].Database | Should -BeExactly "master"
            $loginRows[0].IsFixedRole | Should -BeTrue
        }

        It "fails cleanly without the credential: a warning and no output" {
            $result = Get-DbaDbRole -SqlInstance $loginInstance -Database master -WarningVariable warnings -WarningAction SilentlyContinue
            $result | Should -BeNullOrEmpty
            ($warnings -join " ") | Should -BeLike "*Failure*"
        }

        # As the pin: this command gives the nested Get-DbaDatabase -EnableException, so the connection failure throws.
        It "throws without the credential under -EnableException, as the pinned function does" {
            { Get-DbaDbRole -SqlInstance $loginInstance -Database master -EnableException -WarningAction SilentlyContinue } | Should -Throw -ErrorId "dbatools_Get-DbaDatabase*"
        }
    }
}
