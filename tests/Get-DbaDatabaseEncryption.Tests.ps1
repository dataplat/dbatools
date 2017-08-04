$commandname = $MyInvocation.MyCommand.Name.Replace(".ps1","")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

$script:instance1 = "SVTSQLRESTORE"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "testing pester" {
        It "Should report that one account named SA exists" {
            $false | Should Be $true
        }
    }

#    Context "Check that SA account is enabled" {
#            $results = Get-DbaLogin -SqlInstance $script:instance1 -Login sa
#            It "Should say the SA account is disabled FALSE" {
#                $results.IsDisabled | Should Be "False"
#            }
#        }

}