param($ModuleName = 'dbatools')

Describe "Stop-DbaService" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Stop-DbaService
        }
        It "Should have ComputerName as a parameter" {
            $CommandUnderTest | Should -HaveParameter ComputerName
        }
        It "Should have InstanceName as a parameter" {
            $CommandUnderTest | Should -HaveParameter InstanceName
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have Type as a parameter" {
            $CommandUnderTest | Should -HaveParameter Type
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject
        }
        It "Should have Timeout as a parameter" {
            $CommandUnderTest | Should -HaveParameter Timeout
        }
        It "Should have Credential as a parameter" {
            $CommandUnderTest | Should -HaveParameter Credential
        }
        It "Should have Force as a parameter" {
            $CommandUnderTest | Should -HaveParameter Force
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Command actually works" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $global:instance2
            $instanceName = $server.ServiceName
            $computerName = $server.NetName
        }

        It "stops some services" {
            $services = Stop-DbaService -ComputerName $global:instance2 -InstanceName $instanceName -Type Agent
            $services | Should -Not -BeNullOrEmpty
            foreach ($service in $services) {
                $service.State | Should -Be 'Stopped'
                $service.Status | Should -Be 'Successful'
            }
        }

        It "stops specific services based on instance name through pipeline" {
            BeforeAll {
                #Start services using native cmdlets
                if ($instanceName -eq 'MSSQLSERVER') {
                    $serviceName = "SQLSERVERAGENT"
                } else {
                    $serviceName = "SqlAgent`$$instanceName"
                }
                Get-Service -ComputerName $computerName -Name $serviceName | Start-Service -WarningAction SilentlyContinue | Out-Null
            }

            $services = Get-DbaService -ComputerName $global:instance2 -InstanceName $instanceName -Type Agent, Engine | Stop-DbaService
            $services | Should -Not -BeNullOrEmpty
            foreach ($service in $services) {
                $service.State | Should -Be 'Stopped'
                $service.Status | Should -Be 'Successful'
            }
        }

        AfterAll {
            #Start services using native cmdlets
            if ($instanceName -eq 'MSSQLSERVER') {
                $serviceName = "MSSQLSERVER", "SQLSERVERAGENT"
            } else {
                $serviceName = "MsSql`$$instanceName", "SqlAgent`$$instanceName"
            }
            foreach ($sn in $servicename) {
                Get-Service -ComputerName $computerName -Name $sn | Start-Service -WarningAction SilentlyContinue | Out-Null
            }
        }
    }
}
