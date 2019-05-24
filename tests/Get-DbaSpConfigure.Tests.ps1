$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Name', 'ExcludeName', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "Get configuration" {
        $server = Connect-DbaInstance -SqlInstance $script:instance1
        $configs = $server.Query("sp_configure")
        $remotequerytimeout = $configs | Where-Object name -match 'remote query timeout'

        It "returns equal to results of the straight T-SQL query" {
            $results = Get-DbaSpConfigure -SqlInstance $script:instance1
            $results.count -eq $configs.count
        }

        It "returns two results" {
            $results = Get-DbaSpConfigure -SqlInstance $script:instance1 -Name RemoteQueryTimeout, AllowUpdates
            $results.Count | Should Be 2
        }

        It "returns two results less than all data" {
            $results = Get-DbaSpConfigure -SqlInstance $script:instance1 -ExcludeName "remote query timeout (s)", AllowUpdates
            $results.Count -eq $configs.count - 2
        }

        It "matches the output of sp_configure " {
            $results = Get-DbaSpConfigure -SqlInstance $script:instance1 -Name RemoteQueryTimeout
            $results.ConfiguredValue -eq $remotequerytimeout.config_value | Should Be $true
            $results.RunningValue -eq $remotequerytimeout.run_value | Should Be $true
        }
    }
}