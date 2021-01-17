$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {

        [array]$knownParameters = 'SqlInstance', 'SqlCredential', 'Name', 'Path', 'Template', 'TargetFilePath', 'TargetFileMetadataPath', 'EnableException'
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    AfterAll {
        $null = Get-DbaXESession -SqlInstance $script:instance2 -Session 'Overly Complex Queries' | Remove-DbaXESession
    }
    Context "Test Importing Session Template" {
        It -Skip "session imports with proper name and non-default target file location" {
            $result = Import-DbaXESessionTemplate -SqlInstance $script:instance2 -Template 'Overly Complex Queries' -TargetFilePath C:\temp
            $result.Name | Should Be "Overly Complex Queries"
            $result.TargetFile -match 'C\:\\temp' | Should Be $true
        }
    }
}