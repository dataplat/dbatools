$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "Get configuration" {
        $server = Connect-DbaInstance -SqlInstance $script:instance1
        $configs = $server.Query("sp_configure")
        $remotequerytimeout = $configs | Where-Object name -match 'remote query timeout'

        It "returns equal to or more results than the straight T-SQL query" {
            $results = Get-DbaSpConfigure -SqlInstance $script:instance1
            $results.count -ge $configs.count
        }

        It "returns two results" {
            $results = Get-DbaSpConfigure -SqlInstance $script:instance1 -ConfigName RemoteQueryTimeout, AllowUpdates
            $results.Count | Should Be 2
        }

        It "matches the output of sp_configure " {
            $results = Get-DbaSpConfigure -SqlInstance $script:instance1 -ConfigName RemoteQueryTimeout
            $results.ConfiguredValue -eq $remotequerytimeout.config_value | Should Be $true
            $results.RunningValue -eq $remotequerytimeout.run_value | Should Be $true
        }
    }
}