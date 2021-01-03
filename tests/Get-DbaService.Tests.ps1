$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$knownParameters = 'ComputerName', 'InstanceName', 'Credential', 'Type', 'ServiceName', 'AdvancedProperties', 'EnableException'
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }

    Context "Validate input" {
        It "Cannot resolve hostname of computer" {
            Mock Resolve-DbaNetworkName { $null }
            { Get-DbaService -ComputerName 'DoesNotExist142' -WarningAction Stop 3> $null } | Should Throw
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {

    Context "Command actually works" {
        $instanceName = (Connect-DbaInstance -SqlInstance $script:instance2).ServiceName

        $results = Get-DbaService -ComputerName $script:instance2

        It "shows some services" {
            $results.DisplayName | Should -Not -BeNullOrEmpty
        }

        $results = Get-DbaService -ComputerName $script:instance2 -Type Agent

        It "shows only one service type" {
            foreach ($result in $results) {
                $result.DisplayName -match "Agent" | Should -BeTrue
            }
        }

        $results = Get-DbaService -ComputerName $script:instance2 -InstanceName $instanceName -Type Agent -AdvancedProperties

        It "shows a service from a specific instance" {
            $results.ServiceType | Should -Be "Agent"
        }

        It "Includes a Clustered Property" {
            $results.Clustered | Should -Not -BeNullOrEmpty
        }

        $service = Get-DbaService -ComputerName $script:instance2 -Type Agent -InstanceName $instanceName

        It "sets startup mode of the service to 'Manual'" {
            { $service.ChangeStartMode('Manual') } | Should -Not -Throw
        }

        $results = Get-DbaService -ComputerName $script:instance2 -Type Agent -InstanceName $instanceName

        It "verifies that startup mode of the service is 'Manual'" {
            $results.StartMode | Should -Be 'Manual'
        }

        $service = Get-DbaService -ComputerName $script:instance2 -Type Agent -InstanceName $instanceName

        It "sets startup mode of the service to 'Automatic'" {
            { $service.ChangeStartMode('Automatic') } | Should -Not -Throw
        }

        $results = Get-DbaService -ComputerName $script:instance2 -Type Agent -InstanceName $instanceName

        It "verifies that startup mode of the service is 'Automatic'" {
            $results.StartMode | Should -Be 'Automatic'
        }
    }
}