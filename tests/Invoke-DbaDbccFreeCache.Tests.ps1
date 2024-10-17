param($ModuleName = 'dbatools')

Describe "Invoke-DbaDbccFreeCache" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Invoke-DbaDbccFreeCache
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Operation as a parameter" {
            $CommandUnderTest | Should -HaveParameter Operation -Type String
        }
        It "Should have InputValue as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputValue -Type String
        }
        It "Should have NoInformationalMessages as a parameter" {
            $CommandUnderTest | Should -HaveParameter NoInformationalMessages -Type Switch
        }
        It "Should have MarkInUseForRemoval as a parameter" {
            $CommandUnderTest | Should -HaveParameter MarkInUseForRemoval -Type Switch
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }

    Context "Command usage" {
        BeforeAll {
            $props = 'ComputerName', 'InstanceName', 'SqlInstance', 'Operation', 'Cmd', 'Output'
        }

        It "returns the right results for FREESYSTEMCACHE" {
            $result = Invoke-DbaDbccFreeCache -SqlInstance $global:instance2 -Operation FreeSystemCache -Confirm:$false
            $result.Operation | Should -Match 'FREESYSTEMCACHE'
            $result.Output | Should -Match 'DBCC execution completed. If DBCC printed error messages, contact your system administrator.'
            foreach ($prop in $props) {
                $result.PSObject.Properties.Name | Should -Contain $prop
            }
        }

        It "returns the right results for FREESESSIONCACHE" {
            $result = Invoke-DbaDbccFreeCache -SqlInstance $global:instance2 -Operation FreeSessionCache -Confirm:$false
            $result.Operation | Should -Match 'FREESESSIONCACHE'
            $result.Output | Should -Match 'DBCC execution completed. If DBCC printed error messages, contact your system administrator.'
        }

        It "returns the right results for FREEPROCCACHE" {
            $result = Invoke-DbaDbccFreeCache -SqlInstance $global:instance2 -Operation FREEPROCCACHE -Confirm:$false
            $result.Operation | Should -Match 'FREEPROCCACHE'
            $result.Output | Should -Match 'DBCC execution completed. If DBCC printed error messages, contact your system administrator.'
        }

        It "returns the right results for FREESESSIONCACHE and using NoInformationalMessages" {
            $result = Invoke-DbaDbccFreeCache -SqlInstance $global:instance2 -Operation FreeSessionCache -NoInformationalMessages -Confirm:$false
            $result.Operation | Should -Match 'FREESESSIONCACHE'
            $result.Output | Should -BeNullOrEmpty
        }
    }
}
