param($ModuleName = 'dbatools')

Describe "Remove-DbaRegServerGroup" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaRegServerGroup
        }

        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Name",
            "InputObject",
            "EnableException",
            "WhatIf",
            "Confirm"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Command usage" {
        BeforeDiscovery {
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }

        BeforeAll {
            $group = "dbatoolsci-group1"
            $newGroup = Add-DbaRegServerGroup -SqlInstance $global:instance1 -Name $group

            $group2 = "dbatoolsci-group1a"
            $newGroup2 = Add-DbaRegServerGroup -SqlInstance $global:instance1 -Name $group2

            $hellagroup = Get-DbaRegServerGroup -SqlInstance $global:instance1 -Id 1 |
                Add-DbaRegServerGroup -Name dbatoolsci-first |
                Add-DbaRegServerGroup -Name dbatoolsci-second |
                Add-DbaRegServerGroup -Name dbatoolsci-third |
                Add-DbaRegServer -ServerName dbatoolsci-test -Description ridiculous
        }

        AfterAll {
            Get-DbaRegServerGroup -SqlInstance $global:instance1 |
                Where-Object Name -match dbatoolsci |
                Remove-DbaRegServerGroup
        }

        It "supports dropping via the pipeline" {
            $results = $newGroup | Remove-DbaRegServerGroup
            $results.Name | Should -Be $group
            $results.Status | Should -Be 'Dropped'
        }

        It "supports dropping manually" {
            $results = Remove-DbaRegServerGroup -SqlInstance $global:instance1 -Name $group2
            $results.Name | Should -Be $group2
            $results.Status | Should -Be 'Dropped'
        }

        It "supports hella long group name" {
            $results = Get-DbaRegServerGroup -SqlInstance $global:instance1 -Group $hellagroup.Group
            $results.Name | Should -Be 'dbatoolsci-third'
        }
    }
}
