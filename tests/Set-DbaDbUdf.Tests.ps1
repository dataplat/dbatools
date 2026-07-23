#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaDbUdf",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            # Generated from designed/Set-DbaDbUdf.json parameters array - exact-match surface law.
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "Schema",
                "Name",
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

        $dbName = "dbatoolsci_setudf_$random"
        $null = New-DbaDatabase -SqlInstance $InstanceSingle -Name $dbName

        # Seed the scalar functions the alter legs act on. Invoke-DbaQuery keeps setup independent of New-DbaDbUdf.
        $seed = @(
            "CREATE FUNCTION dbo.fnEdit() RETURNS int AS BEGIN RETURN 1 END"
            "CREATE FUNCTION dbo.fnPipe1() RETURNS int AS BEGIN RETURN 1 END"
            "CREATE FUNCTION dbo.fnPipe2() RETURNS int AS BEGIN RETURN 1 END"
            "CREATE FUNCTION dbo.fnWhatIf() RETURNS int AS BEGIN RETURN 1 END"
        )
        foreach ($ddl in $seed) {
            $null = Invoke-DbaQuery -SqlInstance $InstanceSingle -Database $dbName -Query $ddl
        }

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Remove-DbaDatabase -SqlInstance $InstanceSingle -Database $dbName -Confirm:$false -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "WhatIf support" {
        It "Gates the alter and changes nothing" {
            # The ShouldProcess text is emitted from the module-scoped hop body and is host-direct, so the
            # distinguishing assertion is that the side effect did NOT happen - the body still returns 1.
            $splatWhatIf = @{
                SqlInstance = $InstanceSingle
                Database    = $dbName
                Name        = "fnWhatIf"
                Definition  = "BEGIN RETURN 2 END"
                WhatIf      = $true
            }
            Set-DbaDbUdf @splatWhatIf

            $after = Get-DbaDbUdf -SqlInstance $InstanceSingle -Database $dbName -Name "fnWhatIf"
            $after.TextBody | Should -BeLike "*RETURN 1*"
            $after.TextBody | Should -Not -BeLike "*RETURN 2*"
        }
    }

    Context "Command behavior" {
        It "Alters a function body via -SqlInstance and re-emits the decorated object" {
            $splatEdit = @{
                SqlInstance     = $InstanceSingle
                Database        = $dbName
                Name            = "fnEdit"
                Definition      = "BEGIN RETURN 42 END"
                EnableException = $true
                Confirm         = $false
            }
            $result = Set-DbaDbUdf @splatEdit
            $result.Name | Should -Be "fnEdit"
            # Decoration parity with Get-DbaDbUdf so Get -> Set -> Get composes.
            $result.ComputerName | Should -Not -BeNullOrEmpty
            $result.Database | Should -Be $dbName
            # The new body is live server-side.
            (Get-DbaDbUdf -SqlInstance $InstanceSingle -Database $dbName -Name "fnEdit").TextBody | Should -BeLike "*RETURN 42*"
        }

        It "Alters multiple piped functions (N in, N out)" {
            # Multi-record piped leg. Two functions piped in from Get-DbaDbUdf must both come back altered, each
            # resolving its own parent.
            $results = Get-DbaDbUdf -SqlInstance $InstanceSingle -Database $dbName -Name "fnPipe1", "fnPipe2" |
                Set-DbaDbUdf -Definition "BEGIN RETURN 99 END" -Confirm:$false
            ($results | Measure-Object).Count | Should -Be 2
            foreach ($name in "fnPipe1", "fnPipe2") {
                (Get-DbaDbUdf -SqlInstance $InstanceSingle -Database $dbName -Name $name).TextBody | Should -BeLike "*RETURN 99*"
            }
        }
    }

    Context "Failure paths" {
        It "Requires either -SqlInstance or an input object" {
            $splatNeither = @{
                Name            = "fnEdit"
                Definition      = "BEGIN RETURN 1 END"
                Confirm         = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warnNeither"
            }
            $results = Set-DbaDbUdf @splatNeither
            $warnNeither | Should -BeLike "*You must supply either -SqlInstance or an Input Object*"
            $results | Should -BeNullOrEmpty
        }
    }
}
