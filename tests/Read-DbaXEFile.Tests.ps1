$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"
$base = (Get-Module -Name dbatools).ModuleBase

# Add-Type -Path "$base\bin\smo\Microsoft.SqlServer.XE.Core.dll"
# Add-Type -Path "$base\bin\smo\Microsoft.SqlServer.XEvent.Configuration.dll"
# Add-Type -Path "$base\bin\smo\Microsoft.SqlServer.XEvent.dll"
# Add-Type -Path "$base\bin\smo\Microsoft.SqlServer.XEvent.Linq.dll"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 4
        $defaultParamCount = 11
        [object[]]$params = (Get-ChildItem function:\Read-DbaXEFile).Parameters.Keys
        $knownParameters = 'Path', 'Exact', 'Raw', 'EnableException'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Verifying command output" {
        It "returns some results" {
            $results = Get-DbaXESession -SqlInstance $script:instance2 | Read-DbaXEFile -Raw -WarningAction SilentlyContinue
            [System.Linq.Enumerable]::Count($results) -gt 1 | Should Be $true
        }
        It "returns some results" {
            $results = Get-DbaXESession -SqlInstance $script:instance2 | Read-DbaXEFile -WarningAction SilentlyContinue
            $results.Count -gt 1 | Should Be $true
        }
    }
}