$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 6
        $defaultParamCount = 11
        [object[]]$params = (Get-ChildItem function:\Watch-DbaXESession).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'Session', 'InputObject', 'Raw', 'EnableException'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}

# This command is special and runs infinitely so don't actually try to run it
Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Command functions as expected" {
        It "warns if SQL instance version is not supported" {
            $results = Watch-DbaXESession -SqlInstance $script:instance1 -Session system_health -WarningAction SilentlyContinue -WarningVariable versionwarn
            $versionwarn -match "Unsupported version" | Should Be $true
        }
    }
}