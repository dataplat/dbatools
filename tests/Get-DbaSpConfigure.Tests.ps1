param($ModuleName = 'dbatools')

Describe "Get-DbaSpConfigure" {
    BeforeAll {
        $commandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        $server = Connect-DbaInstance -SqlInstance $global:instance1
        $configs = $server.Query("sp_configure")
        $remotequerytimeout = $configs | Where-Object name -match 'remote query timeout'
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaSpConfigure
        }
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Name",
                "ExcludeName",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Get configuration" {
        It "returns equal to results of the straight T-SQL query" {
            $results = Get-DbaSpConfigure -SqlInstance $global:instance1
            $results.count | Should -Be $configs.count
        }

        It "returns two results" {
            $results = Get-DbaSpConfigure -SqlInstance $global:instance1 -Name RemoteQueryTimeout, AllowUpdates
            $results.Count | Should -Be 2
        }

        It "returns two results less than all data" {
            $allConfigsCount = (Get-DbaSpConfigure -SqlInstance $global:instance1).Count
            $results = Get-DbaSpConfigure -SqlInstance $global:instance1 -ExcludeName "remote query timeout (s)", AllowUpdates
            $results.Count | Should -Be ($allConfigsCount - 2)
        }

        It "matches the output of sp_configure " {
            $results = Get-DbaSpConfigure -SqlInstance $global:instance1 -Name RemoteQueryTimeout
            $results.ConfiguredValue | Should -Be $remotequerytimeout.config_value
            $results.RunningValue | Should -Be $remotequerytimeout.run_value
        }
    }
}
