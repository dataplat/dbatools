#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaDbPartitionFunction",
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
                "ExcludeDatabase",
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

        $server = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $dbname1 = "dbatoolsci_$(Get-Random)"
        $dbname2 = "dbatoolsci_$(Get-Random)"
        $null = New-DbaDatabase -SqlInstance $server -Name $dbname1
        $null = New-DbaDatabase -SqlInstance $server -Name $dbname2

        $partfun1 = "dbatoolssci_partfun1_$(Get-Random)"
        $partfun2 = "dbatoolssci_partfun2_$(Get-Random)"
        $null = $server.Query("CREATE PARTITION FUNCTION $partfun1 (int) AS RANGE LEFT FOR VALUES (1, 100, 1000);", $dbname1)
        $null = $server.Query("CREATE PARTITION FUNCTION $partfun2 (int) AS RANGE LEFT FOR VALUES (1, 100, 1000);", $dbname2)

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaDatabase -SqlInstance $server -Database $dbname1, $dbname2 -Confirm:$false
    }

    Context "When removing partition functions" {
        It "Removes partition function by SqlInstance and Database" {
            Get-DbaDbPartitionFunction -SqlInstance $server -Database $dbname1 | Should -Not -BeNullOrEmpty
            Remove-DbaDbPartitionFunction -SqlInstance $server -Database $dbname1 -Confirm:$false
            Get-DbaDbPartitionFunction -SqlInstance $server -Database $dbname1 | Should -BeNullOrEmpty
        }

        It "Supports piping partition function objects" {
            Get-DbaDbPartitionFunction -SqlInstance $server -Database $dbname2 | Should -Not -BeNullOrEmpty
            Get-DbaDbPartitionFunction -SqlInstance $server -Database $dbname2 | Remove-DbaDbPartitionFunction -Confirm:$false
            Get-DbaDbPartitionFunction -SqlInstance $server -Database $dbname2 | Should -BeNullOrEmpty
        }
    }
}