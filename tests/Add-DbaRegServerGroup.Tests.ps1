param($ModuleName = 'dbatools')

Describe "Add-DbaRegServerGroup" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Add-DbaRegServerGroup
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Name as a parameter" {
            $CommandUnderTest | Should -HaveParameter Name -Type String
        }
        It "Should have Description as a parameter" {
            $CommandUnderTest | Should -HaveParameter Description -Type String
        }
        It "Should have Group as a parameter" {
            $CommandUnderTest | Should -HaveParameter Group -Type String
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type ServerGroup[]
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }

    Context "Command usage" {
        BeforeAll {
            $group = "dbatoolsci-group1"
            $group2 = "dbatoolsci-group2"
            $description = "group description"
            $descriptionUpdated = "group description updated"
        }
        AfterAll {
            Get-DbaRegServerGroup -SqlInstance $global:instance1 | Where-Object Name -match dbatoolsci | Remove-DbaRegServerGroup -Confirm:$false
        }

        It "adds a registered server group" {
            $results = Add-DbaRegServerGroup -SqlInstance $global:instance1 -Name $group
            $results.Name | Should -Be $group
            $results.SqlInstance | Should -Not -BeNullOrEmpty
        }
        It "adds a registered server group with extended properties" {
            $results = Add-DbaRegServerGroup -SqlInstance $global:instance1 -Name $group2 -Description $description
            $results.Name | Should -Be $group2
            $results.Description | Should -Be $description
            $results.SqlInstance | Should -Not -BeNullOrEmpty
        }
        It "supports hella pipe" {
            $results = Get-DbaRegServerGroup -SqlInstance $global:instance1 -Id 1 |
                Add-DbaRegServerGroup -Name dbatoolsci-first |
                Add-DbaRegServerGroup -Name dbatoolsci-second |
                Add-DbaRegServerGroup -Name dbatoolsci-third |
                Add-DbaRegServer -ServerName dbatoolsci-test -Description ridiculous
            $results.Group | Should -Be 'dbatoolsci-first\dbatoolsci-second\dbatoolsci-third'
        }
        It "adds a registered server group and sub-group when not exists" {
            $results = Add-DbaRegServerGroup -SqlInstance $global:instance1 -Name "$group\$group2" -Description $description
            $results.Name | Should -Be $group2
            $results.SqlInstance | Should -Not -BeNullOrEmpty
        }
        It "updates description of sub-group when it already exists" {
            $results = Add-DbaRegServerGroup -SqlInstance $global:instance1 -Name "$group\$group2" -Description $descriptionUpdated
            $results.Name | Should -Be $group2
            $results.Description | Should -Be $descriptionUpdated
            $results.SqlInstance | Should -Not -BeNullOrEmpty
        }
    }
}
