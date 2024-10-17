param($ModuleName = 'dbatools')

Describe "Get-DbaSpConfigure" {
    BeforeAll {
        $commandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaSpConfigure
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have Name as a parameter" {
            $CommandUnderTest | Should -HaveParameter Name -Type String[] -Not -Mandatory
        }
        It "Should have ExcludeName as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeName -Type String[] -Not -Mandatory
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Not -Mandatory
        }
    }

    Context "Get configuration" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $env:instance1
            $configs = $server.Query("sp_configure")
            $remotequerytimeout = $configs | Where-Object name -match 'remote query timeout'
        }

        It "returns equal to results of the straight T-SQL query" {
            $results = Get-DbaSpConfigure -SqlInstance $env:instance1
            $results.count | Should -Be $configs.count
        }

        It "returns two results" {
            $results = Get-DbaSpConfigure -SqlInstance $env:instance1 -Name RemoteQueryTimeout, AllowUpdates
            $results.Count | Should -Be 2
        }

        It "returns two results less than all data" {
            $results = Get-DbaSpConfigure -SqlInstance $env:instance1 -ExcludeName "remote query timeout (s)", AllowUpdates
            $results.Count | Should -Be ($configs.count - 2)
        }

        It "matches the output of sp_configure " {
            $results = Get-DbaSpConfigure -SqlInstance $env:instance1 -Name RemoteQueryTimeout
            $results.ConfiguredValue | Should -Be $remotequerytimeout.config_value
            $results.RunningValue | Should -Be $remotequerytimeout.run_value
        }
    }
}
