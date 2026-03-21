#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaDbUdf",
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
                "ExcludeSystemUdf",
                "Schema",
                "ExcludeSchema",
                "Name",
                "ExcludeName",
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

        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle
        $dbname1 = "dbatoolsci_$(Get-Random)"
        $null = New-DbaDatabase -SqlInstance $server -Name $dbname1

        $udf1 = "dbatoolssci_udf1_$(Get-Random)"
        $udf2 = "dbatoolssci_udf2_$(Get-Random)"
        $null = $server.Query("CREATE FUNCTION dbo.$udf1 (@a int) RETURNS TABLE AS RETURN (SELECT 1 a);", $dbname1)
        $null = $server.Query("CREATE FUNCTION dbo.$udf2 (@a int) RETURNS TABLE AS RETURN (SELECT 1 a);", $dbname1)

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $null = Remove-DbaDatabase -SqlInstance $server -Database $dbname1

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "Commands work as expected" {
        It "Removes an user defined function" {
            Get-DbaDbUdf -SqlInstance $server -Database $dbname1 -Name $udf1 | Should -Not -BeNullOrEmpty
            Remove-DbaDbUdf -SqlInstance $server -Database $dbname1 -Name $udf1
            Get-DbaDbUdf -SqlInstance $server -Database $dbname1 -Name $udf1 | Should -BeNullOrEmpty
        }

        It "Supports piping user defined function" {
            Get-DbaDbUdf -SqlInstance $server -Database $dbname1 -Name $udf2 | Should -Not -BeNullOrEmpty
            Get-DbaDbUdf -SqlInstance $server -Database $dbname1 -Name $udf2 | Remove-DbaDbUdf
            Get-DbaDbUdf -SqlInstance $server -Database $dbname1 -Name $udf2 | Should -BeNullOrEmpty
        }
    }
}