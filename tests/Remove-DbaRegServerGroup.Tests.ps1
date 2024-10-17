param($ModuleName = 'dbatools')

Describe "Remove-DbaRegServerGroup" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaRegServerGroup
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Name as a parameter" {
            $CommandUnderTest | Should -HaveParameter Name -Type String[]
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Microsoft.SqlServer.Management.RegisteredServers.ServerGroup[]
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
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
                Remove-DbaRegServerGroup -Confirm:$false
        }

        It "supports dropping via the pipeline" {
            $results = $newGroup | Remove-DbaRegServerGroup -Confirm:$false
            $results.Name | Should -Be $group
            $results.Status | Should -Be 'Dropped'
        }

        It "supports dropping manually" {
            $results = Remove-DbaRegServerGroup -Confirm:$false -SqlInstance $global:instance1 -Name $group2
            $results.Name | Should -Be $group2
            $results.Status | Should -Be 'Dropped'
        }

        It "supports hella long group name" {
            $results = Get-DbaRegServerGroup -SqlInstance $global:instance1 -Group $hellagroup.Group
            $results.Name | Should -Be 'dbatoolsci-third'
        }
    }
}
