#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaDbView",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            # Generated from designed/Set-DbaDbView.json parameters array - exact-match surface law.
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "Schema",
                "View",
                "Definition",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $random = Get-Random
        $InstanceSingle = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle

        # Each leg gets its own database so the tests do not couple through shared state.
        $dbBasic = "dbatoolsci_setview_$random"
        $dbPipe1 = "dbatoolsci_setview_p1_$random"
        $dbPipe2 = "dbatoolsci_setview_p2_$random"
        $dbGuard = "dbatoolsci_setview_guard_$random"
        $dbDotted = "dbatoolsci_setview_dot_$random"
        $allDatabases = @($dbBasic, $dbPipe1, $dbPipe2, $dbGuard, $dbDotted)
        $null = New-DbaDatabase -SqlInstance $InstanceSingle -Name $allDatabases

        # Seed the views the tests will alter. Each starts as "SELECT 1 AS x".
        foreach ($dbName in $allDatabases) {
            $null = Invoke-DbaQuery -SqlInstance $InstanceSingle -Database $dbName -Query "CREATE VIEW dbo.vWhatIf AS SELECT 1 AS x;"
            $null = Invoke-DbaQuery -SqlInstance $InstanceSingle -Database $dbName -Query "CREATE VIEW dbo.vBasic AS SELECT 1 AS x;"
            $null = Invoke-DbaQuery -SqlInstance $InstanceSingle -Database $dbName -Query "CREATE VIEW dbo.vPipe AS SELECT 1 AS x;"
        }

        # A view whose name contains a dot. Legal in SQL Server when bracketed, and it is what distinguishes a
        # client-side re-emit filter from one that rebuilds a "schema.name" string and re-parses it as a
        # multi-part name.
        $dottedViewName = "v.dotted"
        $null = Invoke-DbaQuery -SqlInstance $InstanceSingle -Database $dbDotted -Query "CREATE VIEW [dbo].[v.dotted] AS SELECT 1 AS x;"

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Remove-DbaDatabase -SqlInstance $InstanceSingle -Database $allDatabases -Confirm:$false -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "WhatIf support" {
        It "Gates the alter and changes nothing" {
            # The ShouldProcess text is emitted from the module-scoped hop body and is host-direct, so the
            # distinguishing assertion is that the side effect did NOT happen - the body is unchanged.
            $splatWhatIf = @{
                SqlInstance = $InstanceSingle
                Database    = $dbBasic
                View        = "vWhatIf"
                Definition  = "SELECT 99 AS altered"
                WhatIf      = $true
            }
            Set-DbaDbView @splatWhatIf

            # The original column still resolves; the new one does not.
            $stillOriginal = Invoke-DbaQuery -SqlInstance $InstanceSingle -Database $dbBasic -Query "SELECT x FROM dbo.vWhatIf"
            $stillOriginal.x | Should -Be 1
        }
    }

    Context "Command behavior" {
        It "Alters a view body via -SqlInstance and re-emits the decorated object" {
            $splatBasic = @{
                SqlInstance     = $InstanceSingle
                Database        = $dbBasic
                View            = "vBasic"
                Definition      = "SELECT 42 AS answer"
                EnableException = $true
                Confirm         = $false
            }
            $result = Set-DbaDbView @splatBasic
            $result.Name | Should -Be "vBasic"
            # Decoration parity with Get-DbaDbView so Get -> Set -> Get composes.
            $result.ComputerName | Should -Not -BeNullOrEmpty
            $result.InstanceName | Should -Not -BeNullOrEmpty
            $result.SqlInstance | Should -Not -BeNullOrEmpty
            $result.Database | Should -Be $dbBasic
            # The body actually changed: the new column resolves and returns the new value.
            $altered = Invoke-DbaQuery -SqlInstance $InstanceSingle -Database $dbBasic -Query "SELECT answer FROM dbo.vBasic"
            $altered.answer | Should -Be 42
        }

        It "Alters views in multiple piped databases (N in, N out)" {
            # Multi-record piped leg. Two views piped in from Get-DbaDbView must both come back altered, each
            # resolving its own parent server.
            $results = Get-DbaDbView -SqlInstance $InstanceSingle -Database $dbPipe1, $dbPipe2 -View "vPipe" |
                Set-DbaDbView -Definition "SELECT 7 AS seven" -Confirm:$false
            ($results | Measure-Object).Count | Should -Be 2
            (Invoke-DbaQuery -SqlInstance $InstanceSingle -Database $dbPipe1 -Query "SELECT seven FROM dbo.vPipe").seven | Should -Be 7
            (Invoke-DbaQuery -SqlInstance $InstanceSingle -Database $dbPipe2 -Query "SELECT seven FROM dbo.vPipe").seven | Should -Be 7
        }

        It "Re-emits a view whose name contains a dot" {
            # The altered view is looked up again so its decoration matches Get-DbaDbView exactly. If that lookup
            # rebuilds "$Schema.$Name" and hands it back to -View, the string is re-parsed as a multi-part name
            # (dbo.v.dotted -> database dbo, schema v, view dotted), which matches nothing: the ALTER lands but the
            # command emits an empty pipeline. The alter and the emit are asserted separately for that reason.
            $viewToAlter = Get-DbaDbView -SqlInstance $InstanceSingle -Database $dbDotted |
                Where-Object Name -eq $dottedViewName
            $result = $viewToAlter | Set-DbaDbView -Definition "SELECT 13 AS dotted" -EnableException -Confirm:$false

            ($result | Measure-Object).Count | Should -Be 1
            $result.Name | Should -Be $dottedViewName
            $result.Database | Should -Be $dbDotted
            $altered = Invoke-DbaQuery -SqlInstance $InstanceSingle -Database $dbDotted -Query "SELECT dotted FROM [dbo].[v.dotted]"
            $altered.dotted | Should -Be 13
        }
    }

    Context "Target requirement" {
        It "Refuses an unfiltered instance-wide alter and changes nothing" {
            # A call with -SqlInstance but neither -View nor -InputObject must not silently rewrite every view in
            # the database. The guard refuses it; the distinguishing assertion is that an unrelated seeded view in
            # the target database was NOT mass-altered - without the guard it would have become "SELECT 999 AS mass".
            $splatUnfiltered = @{
                SqlInstance     = $InstanceSingle
                Database        = $dbGuard
                Definition      = "SELECT 999 AS mass"
                Confirm         = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warnTarget"
            }
            $results = Set-DbaDbView @splatUnfiltered
            $warnTarget | Should -BeLike "*You must specify the target view*"
            $results | Should -BeNullOrEmpty
            # The seeded body still resolves and the mass column never existed.
            $untouched = Invoke-DbaQuery -SqlInstance $InstanceSingle -Database $dbGuard -Query "SELECT x FROM dbo.vWhatIf"
            $untouched.x | Should -Be 1
        }

        It "Refuses to alter a system view" {
            # System views are refused unconditionally (no -Force). Pipe one in so the target guard is satisfied
            # and the system-object guard is the leg under test. The system view is sourced from the test's own
            # database (every database exposes INFORMATION_SCHEMA views) so the leg stays hermetic.
            $systemView = Get-DbaDbView -SqlInstance $InstanceSingle -Database $dbGuard |
                Where-Object IsSystemObject | Select-Object -First 1
            $splatSystem = @{
                Definition      = "SELECT 1 AS x"
                Confirm         = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warnSystem"
            }
            $results = $systemView | Set-DbaDbView @splatSystem
            $warnSystem | Should -BeLike "*is a system object and will not be altered*"
            $results | Should -BeNullOrEmpty
        }
    }

    Context "Failure paths" {
        It "Requires either -SqlInstance or an input object" {
            $splatNeither = @{
                View            = "vBasic"
                Definition      = "SELECT 1 AS x"
                Confirm         = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warnNeither"
            }
            $results = Set-DbaDbView @splatNeither
            $warnNeither | Should -BeLike "*You must supply either -SqlInstance or an Input Object*"
            $results | Should -BeNullOrEmpty
        }

        It "Alters nothing and emits nothing when -View resolves to no view" {
            # An unresolved -View is not an error and not a warning: view resolution runs through Get-DbaDbView,
            # which reports a name it cannot find at Verbose level only. The contract asserted here is the whole
            # contract - no output, no warning, and above all no fallback to altering every view in the database.
            $splatMissing = @{
                SqlInstance     = $InstanceSingle
                Database        = $dbGuard
                View            = "does_not_exist_$random"
                Definition      = "SELECT 555 AS mass"
                Confirm         = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warnMissing"
            }
            $results = Set-DbaDbView @splatMissing
            $results | Should -BeNullOrEmpty
            $warnMissing | Should -BeNullOrEmpty
            # The seeded bodies in the target database are untouched; the mass column never existed.
            (Invoke-DbaQuery -SqlInstance $InstanceSingle -Database $dbGuard -Query "SELECT x FROM dbo.vPipe").x | Should -Be 1
        }

        It "Throws a terminating error with -EnableException on a bad definition" {
            $splatThrow = @{
                SqlInstance     = $InstanceSingle
                Database        = $dbBasic
                View            = "vBasic"
                Definition      = "THIS IS NOT VALID SQL @@@"
                Confirm         = $false
                EnableException = $true
            }
            { Set-DbaDbView @splatThrow } | Should -Throw
        }
    }
}
