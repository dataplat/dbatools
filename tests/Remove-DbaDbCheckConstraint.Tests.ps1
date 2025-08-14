#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Remove-DbaDbCheckConstraint",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "ExcludeDatabase",
                "ExcludeSystemTable",
                "InputObject",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $dbname1 = "dbatoolsci_$(Get-Random)"
        $dbname2 = "dbatoolsci_$(Get-Random)"
        $null = New-DbaDatabase -SqlInstance $server -Name $dbname1
        $null = New-DbaDatabase -SqlInstance $server -Name $dbname2

        $chkc1 = "dbatoolssci_chkc1_$(Get-Random)"
        $chkc2 = "dbatoolssci_chkc2_$(Get-Random)"
        $null = $server.Query("CREATE TABLE dbo.checkconstraint1(col int CONSTRAINT $chkc1 CHECK(col > 0));", $dbname1)
        $null = $server.Query("CREATE TABLE dbo.checkconstraint2(col int CONSTRAINT $chkc2 CHECK(col > 0));", $dbname2)

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaDatabase -SqlInstance $server -Database $dbname1, $dbname2 -Confirm:$false

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    Context "commands work as expected" {
        It "removes an check constraint" {
            Get-DbaDbCheckConstraint -SqlInstance $server -Database $dbname1 | Should -Not -BeNullOrEmpty
            Remove-DbaDbCheckConstraint -SqlInstance $server -Database $dbname1 -Confirm:$false
            Get-DbaDbCheckConstraint -SqlInstance $server -Database $dbname1 | Should -BeNullOrEmpty
        }

        It "supports piping check constraint" {
            Get-DbaDbCheckConstraint -SqlInstance $server -Database $dbname2 | Should -Not -BeNullOrEmpty
            Get-DbaDbCheckConstraint -SqlInstance $server -Database $dbname2 | Remove-DbaDbCheckConstraint -Confirm:$false
            Get-DbaDbCheckConstraint -SqlInstance $server -Database $dbname2 | Should -BeNullOrEmpty
        }
    }
}
