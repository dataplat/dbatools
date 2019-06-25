$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"
. "$PSScriptRoot\..\internal\functions\Connect-SqlInstance.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'ComputerName', 'InstanceName', 'Credential', 'Type', 'ServiceName', 'AdvancedProperties', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }

    Context "Validate input" {
        It "Cannot resolve hostname of computer" {
            mock Resolve-DbaNetworkName {$null}
            {Get-DbaService -ComputerName 'DoesNotExist142' -WarningAction Stop 3> $null} | Should Throw
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {

    Context "Command actually works" {
        $instanceName = (Connect-SqlInstance -SqlInstance $script:instance2).ServiceName

        $results = Get-DbaService -ComputerName $script:instance2

        It "shows some services" {
            $results.DisplayName | Should Not Be $null
        }

        $results = Get-DbaService -ComputerName $script:instance2 -Type Agent

        It "shows only one service type" {
            foreach ($result in $results) {
                $result.DisplayName -match "Agent" | Should Be $true
            }
        }

        $results = Get-DbaService -ComputerName $script:instance2 -InstanceName $instanceName -Type Agent -AdvancedProperties

        It "shows a service from a specific instance" {
            $results.ServiceType| Should Be "Agent"
        }

        It "Includes a Clustered Property" {
            $results.Clustered | Should Not Be $null
        }

        $service = Get-DbaService -ComputerName $script:instance2 -Type Agent -InstanceName $instanceName

        It "sets startup mode of the service to 'Manual'" {
            { $service.ChangeStartMode('Manual') } | Should Not Throw
        }

        $results = Get-DbaService -ComputerName $script:instance2 -Type Agent -InstanceName $instanceName

        It "verifies that startup mode of the service is 'Manual'" {
            $results.StartMode | Should Be 'Manual'
        }

        $service = Get-DbaService -ComputerName $script:instance2 -Type Agent -InstanceName $instanceName

        It "sets startup mode of the service to 'Automatic'" {
            { $service.ChangeStartMode('Automatic') } | Should Not Throw
        }

        $results = Get-DbaService -ComputerName $script:instance2 -Type Agent -InstanceName $instanceName

        It "verifies that startup mode of the service is 'Automatic'" {
            $results.StartMode | Should Be 'Automatic'
        }
    }
}