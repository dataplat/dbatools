$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

$base = (Get-Module -Name dbatools).ModuleBase

Add-Type -Path "$base\bin\smo\Microsoft.SqlServer.XE.Core.dll"
Add-Type -Path "$base\bin\smo\Microsoft.SqlServer.XEvent.Configuration.dll"
Add-Type -Path "$base\bin\smo\Microsoft.SqlServer.XEvent.dll"
Add-Type -Path "$base\bin\smo\Microsoft.SqlServer.XEvent.Linq.dll"

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Verifying command output" {
        It "returns some results" {
            $results = Get-DbaXESession -SqlInstance $script:instance2 | Read-DbaXEFile -Raw
            [System.Linq.Enumerable]::Count($results) -gt 1 | Should Be $true
        }
        It "returns some results" {
            $results = Get-DbaXESession -SqlInstance $script:instance2 | Read-DbaXEFile
            $results.Count -gt 1 | Should Be $true
        }
    }
}