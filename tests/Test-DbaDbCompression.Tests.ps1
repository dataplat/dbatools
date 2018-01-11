$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "command can run" {
        It "should be able to run - not much to test here" {
            Test-DbaDbCompression -SqlInstance $script:instance2 -Database tempdb | Should Be $null
        }
    }
}