$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag "UnitTests" {
    BeforeAll {
        # Command under test
        $CommandUnderTest = Get-Command $CommandName
    }

    Context "Validate parameters" {
        It "Should have the expected parameters" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter Name -Type String -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter Description -Type String -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter Group -Type String -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter InputObject -Type ServerGroup[] -Not -Mandatory
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter -Not -Mandatory
        }

        It "Should only contain our specific parameters" {
            $knownParameters = 'SqlInstance', 'SqlCredential', 'Name', 'Description', 'Group', 'InputObject', 'EnableException'
            $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
            $CommandUnderTest.Parameters.Keys | Where-Object {$_ -notin $knownParameters} | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $group = "dbatoolsci-group1"
        $group2 = "dbatoolsci-group2"
        $description = "group description"
        $descriptionUpdated = "group description updated"
    }

    AfterAll {
        Get-DbaRegServerGroup -SqlInstance $script:instance1 | Where-Object Name -match dbatoolsci | Remove-DbaRegServerGroup -Confirm:$false
    }

    Context "Adding registered server groups" {
        It "adds a registered server group" {
            $results = Add-DbaRegServerGroup -SqlInstance $script:instance1 -Name $group
            $results.Name | Should -Be $group
            $results.SqlInstance | Should -Not -BeNullOrEmpty
        }

        It "adds a registered server group with extended properties" {
            $results = Add-DbaRegServerGroup -SqlInstance $script:instance1 -Name $group2 -Description $description
            $results.Name | Should -Be $group2
            $results.Description | Should -Be $description
            $results.SqlInstance | Should -Not -BeNullOrEmpty
        }

        It "supports piping" {
            $results = Get-DbaRegServerGroup -SqlInstance $script:instance1 -Id 1 | 
                Add-DbaRegServerGroup -Name dbatoolsci-first | 
                Add-DbaRegServerGroup -Name dbatoolsci-second | 
                Add-DbaRegServerGroup -Name dbatoolsci-third | 
                Add-DbaRegServer -ServerName dbatoolsci-test -Description ridiculous
            $results.Group | Should -Be 'dbatoolsci-first\dbatoolsci-second\dbatoolsci-third'
        }

        It "adds a registered server group and sub-group when not exists" {
            $results = Add-DbaRegServerGroup -SqlInstance $script:instance1 -Name "$group\$group2" -Description $description
            $results.Name | Should -Be $group2
            $results.SqlInstance | Should -Not -BeNullOrEmpty
        }

        It "updates description of sub-group when it already exists" {
            $results = Add-DbaRegServerGroup -SqlInstance $script:instance1 -Name "$group\$group2" -Description $descriptionUpdated
            $results.Name | Should -Be $group2
            $results.Description | Should -Be $descriptionUpdated
            $results.SqlInstance | Should -Not -BeNullOrEmpty
        }
    }
}
