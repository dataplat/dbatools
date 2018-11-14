$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 7
        $defaultParamCount = 11
        [object[]]$params = (Get-ChildItem function:\Export-DbaDiagnosticQuery).Parameters.Keys
        $knownParameters = 'InputObject', 'ConvertTo', 'Path', 'Suffix', 'NoPlanExport', 'NoQueryExport', 'EnableException'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    AfterAll {
        (Get-ChildItem "$env:temp\dbatoolsci") | Remove-Item -ErrorAction Ignore
    }
    Context "Verifying output" {
        It "exports results to one file and creates directory if required" {
            $results = Invoke-DbaDiagnosticQuery -SqlInstance $script:instance2 -QueryName 'Memory Clerk Usage' | Export-DbaDiagnosticQuery -Path "$env:temp\dbatoolsci"
            (Get-ChildItem "$env:temp\dbatoolsci").Count | Should Be 1
        }
    }
}