$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {

        [array]$knownParameters = 'ComputerName', 'Credential', 'VersionNumber', 'EnableException'
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}
Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $versionMajor = (Connect-DbaInstance -SqlInstance $script:instance2).VersionMajor
    }
    Context "Command actually works" {
        $trueResults = Test-DbaManagementObject -ComputerName $script:instance2 -VersionNumber $versionMajor
        It "Should have correct properties" {
            $ExpectedProps = 'ComputerName,Version,Exists'.Split(',')
            ($trueResults[0].PsObject.Properties.Name | Sort-Object) | Should Be ($ExpectedProps | Sort-Object)
        }

        It "Should return true for VersionNumber $versionMajor" {
            $trueResults.Exists | Should Be $true
        }

        $falseResults = Test-DbaManagementObject -ComputerName $script:instance2 -VersionNumber -1
        It "Should return false for VersionNumber -1" {
            $falseResults.Exists | Should Be $false
        }
    }
}