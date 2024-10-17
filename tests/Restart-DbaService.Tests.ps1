param($ModuleName = 'dbatools')

Describe "Restart-DbaService" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Restart-DbaService
        }
        It "Should have ComputerName as a non-mandatory parameter of type DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter ComputerName -Type DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have InstanceName as a non-mandatory parameter of type String[]" {
            $CommandUnderTest | Should -HaveParameter InstanceName -Type String[] -Mandatory:$false
        }
        It "Should have SqlInstance as a non-mandatory parameter of type DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have Type as a non-mandatory parameter of type String[]" {
            $CommandUnderTest | Should -HaveParameter Type -Type String[] -Mandatory:$false
        }
        It "Should have InputObject as a non-mandatory parameter of type Object[]" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Object[] -Mandatory:$false
        }
        It "Should have Timeout as a non-mandatory parameter of type Int32" {
            $CommandUnderTest | Should -HaveParameter Timeout -Type Int32 -Mandatory:$false
        }
        It "Should have Credential as a non-mandatory parameter of type PSCredential" {
            $CommandUnderTest | Should -HaveParameter Credential -Type PSCredential -Mandatory:$false
        }
        It "Should have Force as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter Force -Type Switch -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Mandatory:$false
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
