param($ModuleName = 'dbatools')

Describe "Invoke-DbaDbccDropCleanBuffer" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Invoke-DbaDbccDropCleanBuffer
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have NoInformationalMessages as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter NoInformationalMessages -Type switch
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type switch
        }
    }

    Context "Validate standard output" {
        BeforeAll {
            $result = Invoke-DbaDbccDropCleanBuffer -SqlInstance $script:instance1 -Confirm:$false
        }

        It "Should return property: ComputerName" {
            $result.PSObject.Properties['ComputerName'] | Should -Not -BeNullOrEmpty
        }
        It "Should return property: InstanceName" {
            $result.PSObject.Properties['InstanceName'] | Should -Not -BeNullOrEmpty
        }
        It "Should return property: SqlInstance" {
            $result.PSObject.Properties['SqlInstance'] | Should -Not -BeNullOrEmpty
        }
        It "Should return property: Cmd" {
            $result.PSObject.Properties['Cmd'] | Should -Not -BeNullOrEmpty
        }
        It "Should return property: Output" {
            $result.PSObject.Properties['Output'] | Should -Not -BeNullOrEmpty
        }
    }

    Context "Works correctly" {
        It "returns results" {
            $result = Invoke-DbaDbccDropCleanBuffer -SqlInstance $script:instance1 -Confirm:$false
            $result.Output | Should -Match 'DBCC execution completed. If DBCC printed error messages, contact your system administrator.'
        }

        It "returns the right results for -NoInformationalMessages" {
            $result = Invoke-DbaDbccDropCleanBuffer -SqlInstance $script:instance1 -NoInformationalMessages -Confirm:$false
            $result.Cmd | Should -Match 'DBCC DROPCLEANBUFFERS WITH NO_INFOMSGS'
            $result.Output | Should -BeNullOrEmpty
        }
    }
}
