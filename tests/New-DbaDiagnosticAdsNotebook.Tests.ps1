$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {

        [array]$knownParameters = 'SqlInstance', 'SqlCredential', 'TargetVersion', 'Path', 'IncludeDatabaseSpecific', 'EnableException'
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $file = "c:\temp\myNotebook.ipynb"
    }
    AfterAll {
        $null = Remove-Item -Path $file -ErrorAction SilentlyContinue
    }
    Context "creates notebook" {
        It "should create a file" {
            $notebook = New-DbaDiagnosticAdsNotebook -TargetVersion 2017 -Path $file -IncludeDatabaseSpecific
            $notebook | Should Not BeNullOrEmpty
        }

        It "returns a file that includes specific phrases" {
            $results = New-DbaDiagnosticAdsNotebook -TargetVersion 2017 -Path $file -IncludeDatabaseSpecific
            $results | Should Not BeNullOrEmpty
            ($results | Get-Content) -contains "information for current instance"
        }
    }
}