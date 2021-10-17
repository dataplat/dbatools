$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"
$sourcePath = [IO.Path]::Combine((Split-Path $PSScriptRoot -Parent), 'src')
. "$sourcePath\functions\Test-DbaDeprecatedFeature.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'InputObject', 'EnableException'

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}
Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Command actually works" {
        It "Should return a result" {
            $results = Test-DbaDeprecatedFeature -SqlInstance $script:instance2
            $results | Should -Not -Be $null
        }

        It "Should return a result for a database" {
            $results = Test-DbaDeprecatedFeature -SqlInstance $script:instance2 -Database Master
            $results | Should -Not -Be $null
        }
    }
}