$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"
. "$PSScriptRoot\..\internal\functions\Connect-SqlInstance.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        $paramCount = 8
        $defaultParamCount = 13
        [object[]]$params = (Get-ChildItem function:\Restart-DbaService).Parameters.Keys
        $knownParameters = 'ComputerName', 'InstanceName', 'Type', 'InputObject', 'Timeout', 'Credential', 'Force', 'EnableException'
        It "Should contain our specific parameters" {
            ( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
        }
        It "Should only contain $paramCount parameters" {
            $params.Count - $defaultParamCount | Should Be $paramCount
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {

    Context "Command actually works" {

        $instanceName = (Connect-SqlInstance -SqlInstance $script:instance2).ServiceName
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