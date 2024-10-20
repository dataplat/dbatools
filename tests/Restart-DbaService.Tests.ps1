param($ModuleName = 'dbatools')

Describe "Restart-DbaService" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Restart-DbaService
        }

        $params = @(
            "ComputerName",
            "InstanceName",
            "SqlInstance",
            "Type",
            "InputObject",
            "Timeout",
            "Credential",
            "Force",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Command actually works" {
        BeforeAll {
            $instanceName = (Connect-DbaInstance -SqlInstance $global:instance2).ServiceName
        }

        It "restarts some services" {
            $services = Restart-DbaService -ComputerName $global:instance2 -InstanceName $instanceName -Type Agent
            $services | Should -Not -BeNullOrEmpty
            foreach ($service in $services) {
                $service.State | Should -Be 'Running'
                $service.Status | Should -Be 'Successful'
            }
        }

        It "restarts some services through pipeline" {
            $services = Get-DbaService -ComputerName $global:instance2 -InstanceName $instanceName -Type Agent, Engine | Restart-DbaService
            $services | Should -Not -BeNullOrEmpty
            foreach ($service in $services) {
                $service.State | Should -Be 'Running'
                $service.Status | Should -Be 'Successful'
            }
        }
    }
}
