#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaRegServerGroup",
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
                "Name",
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

        # Set variables. They are available in all the It blocks.
        $groupName1 = "dbatoolsci-group1"
        $groupName2 = "dbatoolsci-group1a"

        # Create the objects.
        $newGroup = Add-DbaRegServerGroup -SqlInstance $TestConfig.instance1 -Name $groupName1
        $newGroup2 = Add-DbaRegServerGroup -SqlInstance $TestConfig.instance1 -Name $groupName2

        $hellagroup = Get-DbaRegServerGroup -SqlInstance $TestConfig.instance1 -Id 1 | Add-DbaRegServerGroup -Name dbatoolsci-first | Add-DbaRegServerGroup -Name dbatoolsci-second | Add-DbaRegServerGroup -Name dbatoolsci-third | Add-DbaRegServer -ServerName dbatoolsci-test -Description ridiculous

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        # Cleanup all created objects.
        Get-DbaRegServerGroup -SqlInstance $TestConfig.instance1 | Where-Object Name -match dbatoolsci | Remove-DbaRegServerGroup -Confirm:$false

        # As this is the last block we do not need to reset the $PSDefaultParameterValues.
    }

    Context "When removing registered server groups" {
        It "supports dropping via the pipeline" {
            $results = $newGroup | Remove-DbaRegServerGroup -Confirm:$false
            $results.Name | Should -Be $groupName1
            $results.Status | Should -Be "Dropped"
        }

        It "supports dropping manually" {
            $results = Remove-DbaRegServerGroup -Confirm:$false -SqlInstance $TestConfig.instance1 -Name $groupName2
            $results.Name | Should -Be $groupName2
            $results.Status | Should -Be "Dropped"
        }

        It "supports hella long group name" {
            $results = Get-DbaRegServerGroup -SqlInstance $TestConfig.instance1 -Group $hellagroup.Group
            $results.Name | Should -Be "dbatoolsci-third"
        }
    }
}