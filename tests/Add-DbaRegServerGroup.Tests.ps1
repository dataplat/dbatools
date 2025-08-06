#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName               = "dbatools",
    $CommandName              = [System.IO.Path]::GetFileName($PSCommandPath.Replace('.Tests.ps1', '')),
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe "Add-DbaRegServerGroup" -Tag "UnitTests" {
    Context "Parameter validation" {
        BeforeAll {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $_ -notin ('WhatIf', 'Confirm') }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Name",
                "Description",
                "Group",
                "InputObject",
                "EnableException"
            )
        }

        It "Should have the expected parameters" {
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe "Add-DbaRegServerGroup" -Tag "IntegrationTests" {
    BeforeAll {
        $group = "dbatoolsci-group1"
        $group2 = "dbatoolsci-group2"
        $description = "group description"
        $descriptionUpdated = "group description updated"
    }
    AfterAll {
        Get-DbaRegServerGroup -SqlInstance $TestConfig.instance1 | Where-Object Name -match dbatoolsci | Remove-DbaRegServerGroup -Confirm:$false
    }

    Context "When adding a registered server group" {
        It "adds a registered server group" {
            $results = Add-DbaRegServerGroup -SqlInstance $TestConfig.instance1 -Name $group
            $results.Name | Should -Be $group
            $results.SqlInstance | Should -Not -BeNullOrEmpty
        }

        It "adds a registered server group with extended properties" {
            $results = Add-DbaRegServerGroup -SqlInstance $TestConfig.instance1 -Name $group2 -Description $description
            $results.Name | Should -Be $group2
            $results.Description | Should -Be $description
            $results.SqlInstance | Should -Not -BeNullOrEmpty
        }
    }

    Context "When using pipeline input" {
        It "supports pipeline input" {
            $results = Get-DbaRegServerGroup -SqlInstance $TestConfig.instance1 -Id 1 |
                Add-DbaRegServerGroup -Name dbatoolsci-first |
                Add-DbaRegServerGroup -Name dbatoolsci-second |
                Add-DbaRegServerGroup -Name dbatoolsci-third |
                Add-DbaRegServer -ServerName dbatoolsci-test -Description ridiculous
            $results.Group | Should -Be 'dbatoolsci-first\dbatoolsci-second\dbatoolsci-third'
        }
    }

    Context "When adding nested groups" {
        It "adds a registered server group and sub-group when not exists" {
            $results = Add-DbaRegServerGroup -SqlInstance $TestConfig.instance1 -Name "$group\$group2" -Description $description
            $results.Name | Should -Be $group2
            $results.SqlInstance | Should -Not -BeNullOrEmpty
        }

        It "updates description of sub-group when it already exists" {
            $results = Add-DbaRegServerGroup -SqlInstance $TestConfig.instance1 -Name "$group\$group2" -Description $descriptionUpdated
            $results.Name | Should -Be $group2
            $results.Description | Should -Be $descriptionUpdated
            $results.SqlInstance | Should -Not -BeNullOrEmpty
        }
    }
}
