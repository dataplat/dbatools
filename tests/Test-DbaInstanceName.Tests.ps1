$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"
Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'Blockers', 'ComputerName', 'InstanceName', 'NewServerName', 'RenameRequired', 'ServerName', 'SqlInstance', 'Updatable', 'Warnings'

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}


Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "Command tests servername" {
        $results = Test-DbaInstanceName -SqlInstance $script:instance2
        It "should say rename is not required" {
            $results.RenameRequired | Should -Be $false
        }

        It "returns the correct properties" {
            $ExpectedProps = 'ComputerName,ServerName,RenameRequired,Updatable,Warnings,Blockers,SqlInstance,InstanceName'.Split(',')
            ($results.PsObject.Properties.Name | Sort-Object) | Should -Be ($ExpectedProps | Sort-Object)
        }
    }
}