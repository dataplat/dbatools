#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaDbView",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            # Generated from designed/New-DbaDbView.json parameters array - exact-match surface law.
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "Schema",
                "Name",
                "Definition",
                "Encryption",
                "SchemaBinding",
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
        $dbBasic = "dbatoolsci_newview_$random"
        $dbPipe1 = "dbatoolsci_newview_p1_$random"
        $dbPipe2 = "dbatoolsci_newview_p2_$random"
        $allDatabases = @($dbBasic, $dbPipe1, $dbPipe2)
        $null = New-DbaDatabase -SqlInstance $InstanceSingle -Name $allDatabases

        # A base table for the -SchemaBinding leg: a schema-bound view requires two-part names over a real object.
        $null = Invoke-DbaQuery -SqlInstance $InstanceSingle -Database $dbBasic -Query "CREATE TABLE dbo.bound_source (id int NOT NULL);"

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
        It "Gates the create and changes nothing" {
            # The ShouldProcess text is emitted from the module-scoped hop body and is host-direct, so the
            # distinguishing assertion is that the side effect did NOT happen - no view was created.
            $splatWhatIf = @{
                SqlInstance = $InstanceSingle
                Database    = $dbBasic
                Name        = "vWhatIf"
                Definition  = "SELECT 1 AS x"
                WhatIf      = $true
            }
            New-DbaDbView @splatWhatIf

            $created = Get-DbaDbView -SqlInstance $InstanceSingle -Database $dbBasic -View "vWhatIf"
            $created | Should -BeNullOrEmpty
        }
    }

    Context "Command behavior" {
        It "Creates a view via -SqlInstance and re-emits the decorated object" {
            $splatBasic = @{
                SqlInstance     = $InstanceSingle
                Database        = $dbBasic
                Name            = "vBasic"
                Definition      = "SELECT 1 AS x"
                EnableException = $true
                Confirm         = $false
            }
            $result = New-DbaDbView @splatBasic
            $result.Name | Should -Be "vBasic"
            $result.Schema | Should -Be "dbo"
            # Decoration parity with Get-DbaDbView so Get -> New -> Get composes.
            $result.ComputerName | Should -Not -BeNullOrEmpty
            $result.InstanceName | Should -Not -BeNullOrEmpty
            $result.SqlInstance | Should -Not -BeNullOrEmpty
            $result.Database | Should -Be $dbBasic
            # Read back independently.
            (Get-DbaDbView -SqlInstance $InstanceSingle -Database $dbBasic -View "vBasic").Name | Should -Be "vBasic"
        }

        It "Honors -SchemaBinding as a header option" {
            $splatBound = @{
                SqlInstance     = $InstanceSingle
                Database        = $dbBasic
                Name            = "vBound"
                Definition      = "SELECT id FROM dbo.bound_source"
                SchemaBinding   = $true
                EnableException = $true
                Confirm         = $false
            }
            $result = New-DbaDbView @splatBound
            $result.IsSchemaBound | Should -Be $true
        }

        It "Creates a view in multiple piped databases (N in, N out)" {
            # Multi-record piped leg. Two databases piped in from Get-DbaDatabase must both come back with the
            # created view, each resolving its own parent server.
            $results = Get-DbaDatabase -SqlInstance $InstanceSingle -Database $dbPipe1, $dbPipe2 |
                New-DbaDbView -Name "vPipe" -Definition "SELECT 1 AS x" -Confirm:$false
            ($results | Measure-Object).Count | Should -Be 2
            $results.Name | Sort-Object -Unique | Should -Be "vPipe"
        }
    }

    Context "Failure paths" {
        It "Requires either -SqlInstance or an input object" {
            $splatNeither = @{
                Name            = "vNeither"
                Definition      = "SELECT 1 AS x"
                Confirm         = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warnNeither"
            }
            $results = New-DbaDbView @splatNeither
            $warnNeither | Should -BeLike "*You must supply either -SqlInstance or an Input Object*"
            $results | Should -BeNullOrEmpty
        }

        It "Warns and continues when the view already exists without -EnableException" {
            $null = New-DbaDbView -SqlInstance $InstanceSingle -Database $dbBasic -Name "vDupe" -Definition "SELECT 1 AS x" -Confirm:$false -EnableException
            $splatDupe = @{
                SqlInstance     = $InstanceSingle
                Database        = $dbBasic
                Name            = "vDupe"
                Definition      = "SELECT 1 AS x"
                Confirm         = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warnDupe"
            }
            $results = New-DbaDbView @splatDupe
            $warnDupe | Should -BeLike "*already exists*"
            $results | Should -BeNullOrEmpty
        }

        It "Throws a terminating error with -EnableException" {
            $splatThrow = @{
                SqlInstance     = $InstanceSingle
                Database        = $dbBasic
                Name            = "vDupe"
                Definition      = "SELECT 1 AS x"
                Confirm         = $false
                EnableException = $true
            }
            { New-DbaDbView @splatThrow } | Should -Throw
        }
    }
}
