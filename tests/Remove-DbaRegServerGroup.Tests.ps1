$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tags "UnitTests" {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Name', 'InputObject', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    Context "Setup" {
        BeforeAll {
            $group = "dbatoolsci-group1"
            $newGroup = Add-DbaRegServerGroup -SqlInstance $script:instance1 -Name $group

            $group2 = "dbatoolsci-group1a"
            $newGroup2 = Add-DbaRegServerGroup -SqlInstance $script:instance1 -Name $group2

            $hellagroup = Get-DbaRegServerGroup -SqlInstance $script:instance1 -Id 1 | Add-DbaRegServerGroup -Name dbatoolsci-first | Add-DbaRegServerGroup -Name dbatoolsci-second | Add-DbaRegServerGroup -Name dbatoolsci-third | Add-DbaRegServer -ServerName dbatoolsci-test -Description ridiculous
        }
        AfterAll {
            Get-DbaRegServerGroup -SqlInstance $script:instance1 | Where-Object Name -match dbatoolsci | Remove-DbaRegServerGroup -Confirm:$false
        }

        It "supports dropping via the pipeline" {
            $results = $newGroup | Remove-DbaRegServerGroup -Confirm:$false
            $results.Name | Should -Be $group
            $results.Status | Should -Be 'Dropped'
        }

        It "supports dropping manually" {
            $results = Remove-DbaRegServerGroup -Confirm:$false -SqlInstance $script:instance1 -Name $group2
            $results.Name | Should -Be $group2
            $results.Status | Should -Be 'Dropped'
        }

        It "supports hella long group name" {
            $results = Get-DbaRegServerGroup -SqlInstance $script:instance1 -Group $hellagroup.Group
            $results.Name | Should -Be 'dbatoolsci-third'
        }
    }
}