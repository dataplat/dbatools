$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 12
        $defaultParamCount = 13
        [object[]]$params = (Get-ChildItem function:\New-DbaAgentProxy).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'Name', 'ProxyCredential', 'SubSystem', 'Description', 'Login', 'ServerRole', 'MsdbRole', 'Disabled', 'Force', 'EnableException'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
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