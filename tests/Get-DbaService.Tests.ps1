param($ModuleName = 'dbatools')

Describe "Get-DbaService" {
    BeforeAll {
        $commandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaService
        }
        It "has all the required parameters" {
            $requiredParameters = @(
                "ComputerName",
                "InstanceName",
                "SqlInstance",
                "Credential",
                "Type",
                "ServiceName",
                "AdvancedProperties",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Validate input" {
        BeforeAll {
            Mock -CommandName Resolve-DbaNetworkName -MockWith { $null }
        }
        It "Throws when it cannot resolve hostname of computer" {
            { Get-DbaService -ComputerName 'DoesNotExist142' -WarningAction Stop 3> $null } | Should -Throw
        }
    }

    Context "Command actually works" {
        BeforeAll {
            $instanceName = (Connect-DbaInstance -SqlInstance $global:instance2).ServiceName
            $results = Get-DbaService -ComputerName $global:instance2
            $agentResults = Get-DbaService -ComputerName $global:instance2 -Type Agent
            $advancedResults = Get-DbaService -ComputerName $global:instance2 -InstanceName $instanceName -Type Agent -AdvancedProperties
        }

        It "shows some services" {
            $results.DisplayName | Should -Not -BeNullOrEmpty
        }

        It "shows only one service type" {
            $agentResults | ForEach-Object {
                $_.DisplayName | Should -Match "Agent"
            }
        }

        It "shows a service from a specific instance" {
            $advancedResults.ServiceType | Should -Be "Agent"
        }

        It "Includes a Clustered Property" {
            $advancedResults.Clustered | Should -Not -BeNullOrEmpty
        }

        It "sets startup mode of the service to 'Manual'" {
            $service = Get-DbaService -ComputerName $global:instance2 -Type Agent -InstanceName $instanceName
            { $service.ChangeStartMode('Manual') } | Should -Not -Throw
            $results = Get-DbaService -ComputerName $global:instance2 -Type Agent -InstanceName $instanceName
            $results.StartMode | Should -Be 'Manual'
        }

        It "sets startup mode of the service to 'Automatic'" {
            $service = Get-DbaService -ComputerName $global:instance2 -Type Agent -InstanceName $instanceName
            { $service.ChangeStartMode('Automatic') } | Should -Not -Throw
            $results = Get-DbaService -ComputerName $global:instance2 -Type Agent -InstanceName $instanceName
            $results.StartMode | Should -Be 'Automatic'
        }
    }

    Context "Command actually works with SqlInstance" {
        BeforeAll {
            $results = @( Get-DbaService -SqlInstance $global:instance2 -Type Engine )
        }

        It "shows exactly one service" {
            $results.Count | Should -Be 1
        }
    }
}
