$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tags "UnitTests" {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance','SqlCredential','Name','Description','Group','InputObject','EnableException'
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
            $group2 = "dbatoolsci-group2"
            $description = "group description"
        }
        AfterAll {
            Get-DbaCmsRegServerGroup -SqlInstance $script:instance1 | Where-Object Name -match dbatoolsci | Remove-DbaCmsRegServerGroup -Confirm:$false
        }

        It "adds a registered server group" {
            $results = Add-DbaCmsRegServerGroup -SqlInstance $script:instance1 -Name $group
            $results.Name | Should -Be $group
            $results.SqlInstance | Should -Not -Be $null
        }
        It "adds a registered server group with extended properties" {
            $results = Add-DbaCmsRegServerGroup -SqlInstance $script:instance1 -Name $group2 -Description $description
            $results.Name | Should -Be $group2
            $results.Description | Should -Be $description
            $results.SqlInstance | Should -Not -Be $null
        }
        It "supports hella pipe" {
            $results = Get-DbaCmsRegServerGroup -SqlInstance $script:instance1 -Id 1 | Add-DbaCmsRegServerGroup -Name dbatoolsci-first | Add-DbaCmsRegServerGroup -Name dbatoolsci-second | Add-DbaCmsRegServerGroup -Name dbatoolsci-third | Add-DbaCmsRegServer -ServerName dbatoolsci-test -Description ridiculous
            $results.Group | Should -Be 'dbatoolsci-first\dbatoolsci-second\dbatoolsci-third'
        }
    }
}