param($ModuleName = 'dbatools')

Describe "Start-DbaService" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Start-DbaService
        }
        It "Should have ComputerName parameter" {
            $CommandUnderTest | Should -HaveParameter ComputerName
        }
        It "Should have InstanceName parameter" {
            $CommandUnderTest | Should -HaveParameter InstanceName
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have Type parameter" {
            $CommandUnderTest | Should -HaveParameter Type
        }
        It "Should have InputObject parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have Timeout parameter" {
            $CommandUnderTest | Should -HaveParameter Timeout
        }
        It "Should have Credential parameter" {
            $CommandUnderTest | Should -HaveParameter Credential
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
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
