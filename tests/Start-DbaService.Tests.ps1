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
            $CommandUnderTest | Should -HaveParameter ComputerName -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have InstanceName parameter" {
            $CommandUnderTest | Should -HaveParameter InstanceName -Type String[] -Not -Mandatory
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have Type parameter" {
            $CommandUnderTest | Should -HaveParameter Type -Type String[] -Not -Mandatory
        }
        It "Should have InputObject parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Object[] -Not -Mandatory
        }
        It "Should have Timeout parameter" {
            $CommandUnderTest | Should -HaveParameter Timeout -Type Int32 -Not -Mandatory
        }
        It "Should have Credential parameter" {
            $CommandUnderTest | Should -HaveParameter Credential -Type PSCredential -Not -Mandatory
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Not -Mandatory
        }
    }

    Context "Command actually works" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $env:instance2
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
            $services = Start-DbaService -ComputerName $env:instance2 -Type Agent -InstanceName $instanceName
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

            $services = Get-DbaService -ComputerName $env:instance2 -InstanceName $instanceName -Type Agent, Engine | Start-DbaService
            $services | Should -Not -BeNullOrEmpty
            foreach ($service in $services) {
                $service.State | Should -Be 'Running'
                $service.Status | Should -Be 'Successful'
            }
        }

        It "errors when passing an invalid InstanceName" {
            { Start-DbaService -ComputerName $env:instance2 -Type 'Agent' -InstanceName 'ThisIsInvalid' -EnableException } | Should -Throw 'No SQL Server services found with current parameters.'
        }
    }
}
