param($ModuleName = 'dbatools')

Describe "Start-DbaService" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Start-DbaService
        }

        $params = @(
            "ComputerName",
            "InstanceName",
            "SqlInstance",
            "Type",
            "InputObject",
            "Timeout",
            "Credential",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Command actually works" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $global:instance2
            $instanceName = $server.ServiceName
            $computerName = $server.NetName

            # Stop services using native cmdlets
            if ($instanceName -eq 'MSSQLSERVER') {
                $serviceName = "SQLSERVERAGENT"
            } else {
                $serviceName = "SqlAgent`$$instanceName"
            }
            Get-Service -ComputerName $computerName -Name $serviceName | Stop-Service -WarningAction SilentlyContinue | Out-Null
        }

        It "starts the services back" {
            $services = Start-DbaService -ComputerName $global:instance2 -Type Agent -InstanceName $instanceName
            $services | Should -Not -BeNullOrEmpty
            foreach ($service in $services) {
                $service.State | Should -Be 'Running'
                $service.Status | Should -Be 'Successful'
            }
        }

        It "starts the services back through pipeline" {
            # Stop services using native cmdlets
            if ($instanceName -eq 'MSSQLSERVER') {
                $serviceName = "SQLSERVERAGENT", "MSSQLSERVER"
            } else {
                $serviceName = "SqlAgent`$$instanceName", "MsSql`$$instanceName"
            }
            foreach ($sn in $servicename) { Get-Service -ComputerName $computerName -Name $sn | Stop-Service -WarningAction SilentlyContinue | Out-Null }

            $services = Get-DbaService -ComputerName $global:instance2 -InstanceName $instanceName -Type Agent, Engine | Start-DbaService
            $services | Should -Not -BeNullOrEmpty
            foreach ($service in $services) {
                $service.State | Should -Be 'Running'
                $service.Status | Should -Be 'Successful'
            }
        }

        It "errors when passing an invalid InstanceName" {
            { Start-DbaService -ComputerName $global:instance2 -Type 'Agent' -InstanceName 'ThisIsInvalid' -EnableException } | Should -Throw 'No SQL Server services found with current parameters.'
        }
    }
}
