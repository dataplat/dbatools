$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"
. "$PSScriptRoot\..\internal\functions\Connect-SqlInstance.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {

    Context "Command actually works" {
        $instanceName = (Connect-SqlInstance -SqlInstance $script:instance2).ServiceName

        $results = Get-DbaSqlService -ComputerName $script:instance2

        It "shows some services" {
            $results.DisplayName | Should Not Be $null
        }

        $results = Get-DbaSqlService -ComputerName $script:instance2 -Type Agent

        It "shows only one service type" {
            foreach ($result in $results) {
                $result.DisplayName -match "Agent" | Should Be $true
            }
        }


        $results = Get-DbaSqlService -ComputerName $script:instance2 -InstanceName $instanceName -Type Agent

        It "shows a service from a specific instance" {
            $results.ServiceType| Should Be "Agent"
        }

        $service = Get-DbaSqlService -ComputerName $script:instance2 -Type Agent -InstanceName $instanceName

        It "sets startup mode of the service to 'Manual'" {
            { $service.ChangeStartMode('Manual') } | Should Not Throw
        }

        $results = Get-DbaSqlService -ComputerName $script:instance2 -Type Agent -InstanceName $instanceName

        It "verifies that startup mode of the service is 'Manual'" {
            $results.StartMode | Should Be 'Manual'
        }

        $service = Get-DbaSqlService -ComputerName $script:instance2 -Type Agent -InstanceName $instanceName

        It "sets startup mode of the service to 'Automatic'" {
            { $service.ChangeStartMode('Automatic') } | Should Not Throw
        }

        $results = Get-DbaSqlService -ComputerName $script:instance2 -Type Agent -InstanceName $instanceName

        It "verifies that startup mode of the service is 'Automatic'" {
            $results.StartMode | Should Be 'Automatic'
        }
    }
}