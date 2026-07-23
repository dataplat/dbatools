#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaDbUdf",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            # Generated from designed/New-DbaDbUdf.json parameters array - exact-match surface law.
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "Schema",
                "Name",
                "Definition",
                "FunctionType",
                "DataType",
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
        $dbBasic = "dbatoolsci_newudf_$random"
        $dbPipe1 = "dbatoolsci_newudf_p1_$random"
        $dbPipe2 = "dbatoolsci_newudf_p2_$random"
        $allDatabases = @($dbBasic, $dbPipe1, $dbPipe2)
        $null = New-DbaDatabase -SqlInstance $InstanceSingle -Name $allDatabases

        # A scalar function needs its return DataType - the surface types -DataType as Smo.DataType.
        $intType = New-Object Microsoft.SqlServer.Management.Smo.DataType([Microsoft.SqlServer.Management.Smo.SqlDataType]::Int)

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
            # distinguishing assertion is that the side effect did NOT happen - no function was created.
            $splatWhatIf = @{
                SqlInstance  = $InstanceSingle
                Database     = $dbBasic
                Name         = "fnWhatIf"
                Definition   = "BEGIN RETURN 1 END"
                FunctionType = "Scalar"
                DataType     = $intType
                WhatIf       = $true
            }
            New-DbaDbUdf @splatWhatIf

            $created = Get-DbaDbUdf -SqlInstance $InstanceSingle -Database $dbBasic -Name "fnWhatIf"
            $created | Should -BeNullOrEmpty
        }
    }

    Context "Command behavior" {
        It "Creates a scalar function via -SqlInstance and re-emits the decorated object" {
            $splatBasic = @{
                SqlInstance     = $InstanceSingle
                Database        = $dbBasic
                Name            = "fnBasic"
                Definition      = "BEGIN RETURN 1 END"
                FunctionType    = "Scalar"
                DataType        = $intType
                EnableException = $true
                Confirm         = $false
            }
            $result = New-DbaDbUdf @splatBasic
            $result.Name | Should -Be "fnBasic"
            $result.Schema | Should -Be "dbo"
            # Decoration parity with Get-DbaDbUdf so Get -> New -> Get composes.
            $result.ComputerName | Should -Not -BeNullOrEmpty
            $result.InstanceName | Should -Not -BeNullOrEmpty
            $result.SqlInstance | Should -Not -BeNullOrEmpty
            $result.Database | Should -Be $dbBasic
            # Read back independently.
            (Get-DbaDbUdf -SqlInstance $InstanceSingle -Database $dbBasic -Name "fnBasic").Name | Should -Be "fnBasic"
        }

        It "Creates a function in multiple piped databases (N in, N out)" {
            # Multi-record piped leg. Two databases piped in from Get-DbaDatabase must both come back with the
            # created function, each resolving its own parent server.
            $intTypeLocal = New-Object Microsoft.SqlServer.Management.Smo.DataType([Microsoft.SqlServer.Management.Smo.SqlDataType]::Int)
            $results = Get-DbaDatabase -SqlInstance $InstanceSingle -Database $dbPipe1, $dbPipe2 |
                New-DbaDbUdf -Name "fnPipe" -Definition "BEGIN RETURN 1 END" -FunctionType Scalar -DataType $intTypeLocal -Confirm:$false
            ($results | Measure-Object).Count | Should -Be 2
            $results.Name | Sort-Object -Unique | Should -Be "fnPipe"
        }
    }

    Context "Failure paths" {
        It "Requires either -SqlInstance or an input object" {
            $splatNeither = @{
                Name            = "fnNeither"
                Definition      = "BEGIN RETURN 1 END"
                FunctionType    = "Scalar"
                DataType        = $intType
                Confirm         = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warnNeither"
            }
            $results = New-DbaDbUdf @splatNeither
            $warnNeither | Should -BeLike "*You must supply either -SqlInstance or an Input Object*"
            $results | Should -BeNullOrEmpty
        }

        It "Warns and continues when the function already exists without -EnableException" {
            $null = New-DbaDbUdf -SqlInstance $InstanceSingle -Database $dbBasic -Name "fnDupe" -Definition "BEGIN RETURN 1 END" -FunctionType Scalar -DataType $intType -Confirm:$false -EnableException
            $splatDupe = @{
                SqlInstance     = $InstanceSingle
                Database        = $dbBasic
                Name            = "fnDupe"
                Definition      = "BEGIN RETURN 1 END"
                FunctionType    = "Scalar"
                DataType        = $intType
                Confirm         = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warnDupe"
            }
            $results = New-DbaDbUdf @splatDupe
            $warnDupe | Should -BeLike "*already exists*"
            $results | Should -BeNullOrEmpty
        }
    }
}
