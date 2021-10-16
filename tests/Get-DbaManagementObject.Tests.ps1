$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'ComputerName', 'Credential', 'VersionNumber', 'EnableException'

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}
Describe "Get-DbaManagementObject Integration Test" -Tag "IntegrationTests" {
    $results = Get-DbaManagementObject -ComputerName $env:COMPUTERNAME

    It "returns results" {
        $results.Count -gt 0 | Should Be $true
    }
    It "has the correct properties" {
        $result = $results[0]
        $ExpectedProps = 'ComputerName,Version,Loaded,LoadTemplate'.Split(',')
        ($result.PsObject.Properties.Name | Sort-Object) | Should Be ($ExpectedProps | Sort-Object)
    }

    $results = Get-DbaManagementObject -ComputerName $env:COMPUTERNAME -VersionNumber 16
    It "Returns the version specified" {
        $results | Should Not Be $null
    }
}