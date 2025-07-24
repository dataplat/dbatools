$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Session', 'InputObject', 'Raw', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Command functions as expected" {
        BeforeAll {
            Stop-DbaXESession -SqlInstance $TestConfig.instance2 -Session system_health -EnableException -Confirm:$false
        }
        AfterAll {
            Start-DbaXESession -SqlInstance $TestConfig.instance2 -Session system_health -EnableException -Confirm:$false
        }

        # This command is special and runs infinitely so don't actually try to run it
        It "warns if XE session is not running" {
            $results = Watch-DbaXESession -SqlInstance $TestConfig.instance2 -Session system_health -WarningAction SilentlyContinue -WarningVariable warn
            $warn | Should -Match 'system_health is not running'
        }
    }
}
