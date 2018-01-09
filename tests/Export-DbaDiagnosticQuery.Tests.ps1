$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    AfterAll {
        (Get-ChildItem "$env:temp\dbatoolsci") | Remove-Item
    }
    Context "Verifying output" {
        It "exports results to one file and creates directory if required" {
            $results = Invoke-DbaDiagnosticQuery -SqlInstance $script:instance2 -QueryName 'Memory Clerk Usage' | Export-DbaDiagnosticQuery -Path "$env:temp\dbatoolsci"
            (Get-ChildItem "$env:temp\dbatoolsci").Count | Should Be 1
        }
    }
}