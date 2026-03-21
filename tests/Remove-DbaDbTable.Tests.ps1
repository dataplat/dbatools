#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaDbTable",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "Table",
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

        $InstanceSingle = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $null = Get-DbaProcess -SqlInstance $InstanceSingle | Where-Object Program -match dbatools | Stop-DbaProcess -WarningAction SilentlyContinue
        $dbname1 = "dbatoolsci_$(Get-Random)"
        $null = New-DbaDatabase -SqlInstance $InstanceSingle -Name $dbname1

        $table1 = "dbatoolssci_table1_$(Get-Random)"
        $table2 = "dbatoolssci_table2_$(Get-Random)"
        $null = $InstanceSingle.Query("CREATE TABLE $table1 (Id int IDENTITY PRIMARY KEY, Value int DEFAULT 0);", $dbname1)
        $null = $InstanceSingle.Query("CREATE TABLE $table2 (Id int IDENTITY PRIMARY KEY, Value int DEFAULT 0);", $dbname1)

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaDatabase -SqlInstance $InstanceSingle -Database $dbname1

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Commands work as expected" {
        It "Removes a table" {
            (Get-DbaDbTable -SqlInstance $InstanceSingle -Database $dbname1 -Table $table1) | Should -Not -BeNullOrEmpty
            Remove-DbaDbTable -SqlInstance $InstanceSingle -Database $dbname1 -Table $table1
            (Get-DbaDbTable -SqlInstance $InstanceSingle -Database $dbname1 -Table $table1) | Should -BeNullOrEmpty
        }

        It "Supports piping table" {
            (Get-DbaDbTable -SqlInstance $InstanceSingle -Database $dbname1 -Table $table2) | Should -Not -BeNullOrEmpty
            Get-DbaDbTable -SqlInstance $InstanceSingle -Database $dbname1 -Table $table2 | Remove-DbaDbTable
            (Get-DbaDbTable -SqlInstance $InstanceSingle -Database $dbname1 -Table $table2) | Should -BeNullOrEmpty
        }
    }
}