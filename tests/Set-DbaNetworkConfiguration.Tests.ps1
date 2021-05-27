$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'InputObject', 'Credential', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}
Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Command actually works" {
        $netConf = Get-DbaNetworkConfiguration -SqlInstance $script:instance2
        if ($netConf.NamedPipesEnabled) {
            $netConf.NamedPipesEnabled = $false
        } else {
            $netConf.NamedPipesEnabled = $true
        }
        $results = $netConf | Set-DbaNetworkConfiguration

        It "Should Return a Result" {
            $results.Changes | Should -Match "Changed NamedPipesEnabled to"
        }

        if ($netConf.NamedPipesEnabled) {
            $netConf.NamedPipesEnabled = $false
        } else {
            $netConf.NamedPipesEnabled = $true
        }
        $null = $netConf | Set-DbaNetworkConfiguration
    }
}