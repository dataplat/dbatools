$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'Path', 'Destination', 'EnableException'

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "Get Template Index" {
        $null = Copy-DbaXESessionTemplate *>1
        $source = ((Get-DbaXESessionTemplate -Path $Path | Where-Object Source -ne Microsoft).Path | Select-Object -First 1).Name
        It "copies the files properly" {
            Get-ChildItem "$home\Documents\SQL Server Management Studio\Templates\XEventTemplates" | Where-Object Name -eq $source | Should Not Be Null
        }
    }
}