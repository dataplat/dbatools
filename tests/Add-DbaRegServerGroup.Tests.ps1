$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tags "UnitTests" {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Name', 'Description', 'Group', 'InputObject', 'EnableException'

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    Context "Setup" {
        BeforeAll {
            $group = "dbatoolsci-group1"
            $group2 = "dbatoolsci-group2"
            $description = "group description"
            $descriptionUpdated = "group description updated"
        }
        AfterAll {
            Get-DbaRegServerGroup -SqlInstance $script:instance1 | Where-Object Name -match dbatoolsci | Remove-DbaRegServerGroup -Confirm:$false
        }

        It "adds a registered server group" {
            $results = Add-DbaRegServerGroup -SqlInstance $script:instance1 -Name $group
            $results.Name | Should -Be $group
            $results.SqlInstance | Should -Not -Be $null
        }
        It "adds a registered server group with extended properties" {
            $results = Add-DbaRegServerGroup -SqlInstance $script:instance1 -Name $group2 -Description $description
            $results.Name | Should -Be $group2
            $results.Description | Should -Be $description
            $results.SqlInstance | Should -Not -Be $null
        }
        It "supports hella pipe" {
            $results = Get-DbaRegServerGroup -SqlInstance $script:instance1 -Id 1 | Add-DbaRegServerGroup -Name dbatoolsci-first | Add-DbaRegServerGroup -Name dbatoolsci-second | Add-DbaRegServerGroup -Name dbatoolsci-third | Add-DbaRegServer -ServerName dbatoolsci-test -Description ridiculous
            $results.Group | Should -Be 'dbatoolsci-first\dbatoolsci-second\dbatoolsci-third'
        }
        It "adds a registered server group and sub-group when not exists" {
            $results = Add-DbaRegServerGroup -SqlInstance $script:instance1 -Name "$group\$group2" -Description $description
            $results.Name | Should -Be $group2
            $results.SqlInstance | Should -Not -Be $null
        }
        It "updates description of sub-group when it already exists" {
            $results = Add-DbaRegServerGroup -SqlInstance $script:instance1 -Name "$group\$group2" -Description $descriptionUpdated
            $results.Name | Should -Be $group2
            $results.Description | Should -Be $descriptionUpdated
            $results.SqlInstance | Should -Not -Be $null
        }
    }
}