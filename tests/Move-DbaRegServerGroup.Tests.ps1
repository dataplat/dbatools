#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
        $ModuleName  = "dbatools",
    $CommandName = "Move-DbaRegServerGroup",
    $PSDefaultParameterValues = $TestConfig.Defaults
)
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Group",
                "NewGroup",
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

        $srvName = "dbatoolsci-server1"
        $group = "dbatoolsci-group1"
        $regSrvName = "dbatoolsci-server12"
        $regSrvDesc = "dbatoolsci-server123"

        $newGroup = Add-DbaRegServerGroup -SqlInstance $TestConfig.instance1 -Name $group
        $newServer = Add-DbaRegServer -SqlInstance $TestConfig.instance1 -ServerName $srvName -Name $regSrvName -Description $regSrvDesc -Group $newGroup.Name

        $group2 = "dbatoolsci-group1a"
        $newGroup2 = Add-DbaRegServerGroup -SqlInstance $TestConfig.instance1 -Name $group2

        $group3 = "dbatoolsci-group1b"
        $newGroup3 = Add-DbaRegServerGroup -SqlInstance $TestConfig.instance1 -Name $group3

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Get-DbaRegServer -SqlInstance $TestConfig.instance1 -Name $regSrvName | Remove-DbaRegServer -Confirm:$false -ErrorAction SilentlyContinue
        Get-DbaRegServerGroup -SqlInstance $TestConfig.instance1 -Group $group, $group2, $group3 | Remove-DbaRegServerGroup -Confirm:$false -ErrorAction SilentlyContinue
    }

    Context "When moving registered server groups" {
        It "moves a piped group" {
            $results = $newGroup2, $newGroup3 | Move-DbaRegServerGroup -NewGroup $newGroup.Name
            $results.Parent.Name | Should -Be $newGroup.Name, $newGroup.Name
        }

        It "moves a manually specified group" {
            $results = Move-DbaRegServerGroup -SqlInstance $TestConfig.instance1 -Group "$group\$group3" -NewGroup Default
            $results.Parent.Name | Should -Be "DatabaseEngineServerGroup"
        }
    }
}