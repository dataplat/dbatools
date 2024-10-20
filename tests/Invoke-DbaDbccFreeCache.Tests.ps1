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

        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Operation",
            "InputValue",
            "NoInformationalMessages",
            "MarkInUseForRemoval",
            "EnableException",
            "WhatIf",
            "Confirm"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Command usage" {
        BeforeAll {
            $props = 'ComputerName', 'InstanceName', 'SqlInstance', 'Operation', 'Cmd', 'Output'
        }

        It "returns the right results for FREESYSTEMCACHE" {
            $result = Invoke-DbaDbccFreeCache -SqlInstance $global:instance2 -Operation FreeSystemCache
            $result.Operation | Should -Match 'FREESYSTEMCACHE'
            $result.Output | Should -Match 'DBCC execution completed. If DBCC printed error messages, contact your system administrator.'
            foreach ($prop in $props) {
                $result.PSObject.Properties.Name | Should -Contain $prop
            }
        }

        It "returns the right results for FREESESSIONCACHE" {
            $result = Invoke-DbaDbccFreeCache -SqlInstance $global:instance2 -Operation FreeSessionCache
            $result.Operation | Should -Match 'FREESESSIONCACHE'
            $result.Output | Should -Match 'DBCC execution completed. If DBCC printed error messages, contact your system administrator.'
        }

        It "returns the right results for FREEPROCCACHE" {
            $result = Invoke-DbaDbccFreeCache -SqlInstance $global:instance2 -Operation FREEPROCCACHE
            $result.Operation | Should -Match 'FREEPROCCACHE'
            $result.Output | Should -Match 'DBCC execution completed. If DBCC printed error messages, contact your system administrator.'
        }

        It "returns the right results for FREESESSIONCACHE and using NoInformationalMessages" {
            $result = Invoke-DbaDbccFreeCache -SqlInstance $global:instance2 -Operation FreeSessionCache -NoInformationalMessages
            $result.Operation | Should -Match 'FREESESSIONCACHE'
            $result.Output | Should -BeNullOrEmpty
        }
    }
}
