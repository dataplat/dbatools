#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaDbStoredProcedure",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            # Generated from designed/New-DbaDbStoredProcedure.json parameters array - exact-match surface law.
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
        $dbBasic = "dbatoolsci_newproc_$random"
        $dbPipe1 = "dbatoolsci_newproc_p1_$random"
        $dbPipe2 = "dbatoolsci_newproc_p2_$random"
        $allDatabases = @($dbBasic, $dbPipe1, $dbPipe2)
        $null = New-DbaDatabase -SqlInstance $InstanceSingle -Name $allDatabases

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
            # distinguishing assertion is that the side effect did NOT happen - no procedure was created.
            $splatWhatIf = @{
                SqlInstance = $InstanceSingle
                Database    = $dbBasic
                Name        = "spWhatIf"
                Definition  = "SELECT 1 AS x"
                WhatIf      = $true
            }
            New-DbaDbStoredProcedure @splatWhatIf

            $created = Get-DbaDbStoredProcedure -SqlInstance $InstanceSingle -Database $dbBasic -Name "spWhatIf"
            $created | Should -BeNullOrEmpty
        }
    }

    Context "Command behavior" {
        It "Creates a procedure via -SqlInstance and re-emits the decorated object" {
            $splatBasic = @{
                SqlInstance     = $InstanceSingle
                Database        = $dbBasic
                Name            = "spBasic"
                Definition      = "SELECT 1 AS x"
                EnableException = $true
                Confirm         = $false
            }
            $result = New-DbaDbStoredProcedure @splatBasic
            $result.Name | Should -Be "spBasic"
            $result.Schema | Should -Be "dbo"
            # Decoration parity with Get-DbaDbStoredProcedure so Get -> New -> Get composes.
            $result.ComputerName | Should -Not -BeNullOrEmpty
            $result.InstanceName | Should -Not -BeNullOrEmpty
            $result.SqlInstance | Should -Not -BeNullOrEmpty
            $result.Database | Should -Be $dbBasic
            # Read back independently.
            (Get-DbaDbStoredProcedure -SqlInstance $InstanceSingle -Database $dbBasic -Name "spBasic").Name | Should -Be "spBasic"
        }

        It "Honors -Encryption as a header option" {
            $splatEnc = @{
                SqlInstance     = $InstanceSingle
                Database        = $dbBasic
                Name            = "spEnc"
                Definition      = "SELECT 1 AS x"
                Encryption      = $true
                EnableException = $true
                Confirm         = $false
            }
            $result = New-DbaDbStoredProcedure @splatEnc
            $result.IsEncrypted | Should -Be $true
        }

        It "Creates a procedure in multiple piped databases (N in, N out)" {
            # Multi-record piped leg. Two databases piped in from Get-DbaDatabase must both come back with the
            # created procedure, each resolving its own parent server.
            $results = Get-DbaDatabase -SqlInstance $InstanceSingle -Database $dbPipe1, $dbPipe2 |
                New-DbaDbStoredProcedure -Name "spPipe" -Definition "SELECT 1 AS x" -Confirm:$false
            ($results | Measure-Object).Count | Should -Be 2
            $results.Name | Sort-Object -Unique | Should -Be "spPipe"
        }
    }

    Context "Failure paths" {
        It "Requires either -SqlInstance or an input object" {
            $splatNeither = @{
                Name            = "spNeither"
                Definition      = "SELECT 1 AS x"
                Confirm         = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warnNeither"
            }
            $results = New-DbaDbStoredProcedure @splatNeither
            $warnNeither | Should -BeLike "*You must supply either -SqlInstance or an Input Object*"
            $results | Should -BeNullOrEmpty
        }

        It "Warns and continues when the procedure already exists without -EnableException" {
            $null = New-DbaDbStoredProcedure -SqlInstance $InstanceSingle -Database $dbBasic -Name "spDupe" -Definition "SELECT 1 AS x" -Confirm:$false -EnableException
            $splatDupe = @{
                SqlInstance     = $InstanceSingle
                Database        = $dbBasic
                Name            = "spDupe"
                Definition      = "SELECT 1 AS x"
                Confirm         = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warnDupe"
            }
            $results = New-DbaDbStoredProcedure @splatDupe
            $warnDupe | Should -BeLike "*already exists*"
            $results | Should -BeNullOrEmpty
        }

        It "Throws a terminating error with -EnableException" {
            $splatThrow = @{
                SqlInstance     = $InstanceSingle
                Database        = $dbBasic
                Name            = "spDupe"
                Definition      = "SELECT 1 AS x"
                Confirm         = $false
                EnableException = $true
            }
            { New-DbaDbStoredProcedure @splatThrow } | Should -Throw
        }
    }
}
