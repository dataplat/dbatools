$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 5
        $defaultParamCount = 13
        [object[]]$params = (Get-ChildItem function:\Clear-DbaPlanCache).Parameters.Keys
        $knownParameters = 'SqlInstance', 'SqlCredential', 'Threshold', 'InputObject', 'EnableException'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    Context "doesn't clear plan cache" {
        It "returns correct datatypes" {
            # Make plan cache way higher than likely for a test rig
            $results = Clear-DbaPlanCache -SqlInstance $script:instance1 -Threshold 10240
            $results.Size -is [dbasize] | Should -Be $true
            $results.Status -match 'below' | Should -Be $true
        }
        It "supports piping" {
            # Make plan cache way higher than likely for a test rig
            $results = Get-DbaPlanCache -SqlInstance $script:instance1 | Clear-DbaPlanCache -Threshold 10240
            $results.Size -is [dbasize] | Should -Be $true
            $results.Status -match 'below' | Should -Be $true
        }
    }
}