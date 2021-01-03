$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$knownParameters = 'ComputerName', 'InstanceName', 'Type', 'InputObject', 'Timeout', 'Credential', 'Force', 'EnableException'
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {

    Context "Command actually works" {

        $instanceName = (Connect-DbaInstance -SqlInstance $script:instance2).ServiceName
        It "restarts some services" {
            $services = Restart-DbaService -ComputerName $script:instance2 -InstanceName $instanceName -Type Agent
            $services | Should Not Be $null
            foreach ($service in $services) {
                $service.State | Should Be 'Running'
                $service.Status | Should Be 'Successful'
            }
        }

        It "restarts some services through pipeline" {
            $services = Get-DbaService -ComputerName $script:instance2 -InstanceName $instanceName -Type Agent, Engine | Restart-DbaService
            $services | Should Not Be $null
            foreach ($service in $services) {
                $service.State | Should Be 'Running'
                $service.Status | Should Be 'Successful'
            }
        }
    }
}