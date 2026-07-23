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
        $allDatabases = @($dbBasic, $dbPipe1, $dbPipe2)
        $null = New-DbaDatabase -SqlInstance $InstanceSingle -Name $allDatabases

        # Seed the views the tests will alter. Each starts as "SELECT 1 AS x".
        foreach ($dbName in $allDatabases) {
            $null = Invoke-DbaQuery -SqlInstance $InstanceSingle -Database $dbName -Query "CREATE VIEW dbo.vWhatIf AS SELECT 1 AS x;"
            $null = Invoke-DbaQuery -SqlInstance $InstanceSingle -Database $dbName -Query "CREATE VIEW dbo.vBasic AS SELECT 1 AS x;"
            $null = Invoke-DbaQuery -SqlInstance $InstanceSingle -Database $dbName -Query "CREATE VIEW dbo.vPipe AS SELECT 1 AS x;"
        }

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

        It "Warns and continues on an unknown view without -EnableException" {
            $splatWarn = @{
                SqlInstance     = $InstanceSingle
                Database        = $dbBasic
                View            = "does_not_exist_$random"
                Definition      = "SELECT 1 AS x"
                Confirm         = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warnMissing"
            }
            $results = Set-DbaDbView @splatWarn
            # No view resolved, so nothing is emitted; the run does not throw.
            $results | Should -BeNullOrEmpty
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
