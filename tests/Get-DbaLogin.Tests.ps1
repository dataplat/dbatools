$commandname = $MyInvocation.MyCommand.Name.Replace(".ps1","")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "Does sql instance have a SA account" {
        $results = Get-DbaLogin -SqlInstance $script:instance1 -Login sa 
        It "Should report that one account named SA exists" {
            $results.Count | Should Be 1
        }
    }

    Context "Check that SA account is enabled" {
            $results = Get-DbaLogin -SqlInstance $script:instance1 -Login sa
            It "Should say the SA account is disabled FALSE" {
                $results.IsDisabled | Should Be "False"
            }
        }
}