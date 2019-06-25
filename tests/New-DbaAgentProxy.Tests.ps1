$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Name', 'ProxyCredential', 'SubSystem', 'Description', 'Login', 'ServerRole', 'MsdbRole', 'Disabled', 'Force', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

# This is quite light of a test but setting up a proxy requires a lot of setup and I don't have time today
Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "does not try to add without" {
        $results = New-DbaAgentProxy -SqlInstance $script:instance2 -Name STIG -ProxyCredential 'dbatoolsci_proxytest' -WarningAction SilentlyContinue -WarningVariable warn
        It "does not try to add the proxy without a valid credential" {
            $warn -match 'does not exist' | Should Be $true
        }
    }
}