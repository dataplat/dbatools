$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "Modules are properly retreived" {

        # SQL2008R2SP2 returns around 600 of these in freshly installed instance. 100 is a good enough number.
        It "Should have a high count" {
            $results = Get-DbaSqlModule -SqlInstance $script:instance1 | Select-Object -First 101
            $results.Count | Should BeGreaterThan 100
        }

        # SQL2008R2SP2 will return a number of modules from the msdb database so it is a good candidate to test
        $results = Get-DbaSqlModule -SqlInstance $script:instance1 -Type View -Database msdb
        It "Should only have one type of object" {
            ($results | Select -Unique Database | Measure-Object).Count | Should Be 1
        }

        It "Should only have one database" {
            ($results | Select -Unique Type | Measure-Object).Count | Should Be 1
        }
    }
}