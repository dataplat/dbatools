param($ModuleName = 'dbatools')

Describe "New-DbaLinkedServerLogin" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaLinkedServerLogin
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have LinkedServer parameter" {
            $CommandUnderTest | Should -HaveParameter LinkedServer -Type String[] -Not -Mandatory
        }
        It "Should have LocalLogin parameter" {
            $CommandUnderTest | Should -HaveParameter LocalLogin -Type String -Not -Mandatory
        }
        It "Should have RemoteUser parameter" {
            $CommandUnderTest | Should -HaveParameter RemoteUser -Type String -Not -Mandatory
        }
        It "Should have RemoteUserPassword parameter" {
            $CommandUnderTest | Should -HaveParameter RemoteUserPassword -Type SecureString -Not -Mandatory
        }
        It "Should have Impersonate parameter" {
            $CommandUnderTest | Should -HaveParameter Impersonate -Type Switch -Not -Mandatory
        }
        It "Should have InputObject parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type LinkedServer[] -Not -Mandatory
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Not -Mandatory
        }
    }
}

Describe "New-DbaLinkedServerLogin Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $random = Get-Random
        $instance2 = Connect-DbaInstance -SqlInstance $env:instance2
        $instance3 = Connect-DbaInstance -SqlInstance $env:instance3

        $securePassword = ConvertTo-SecureString -String 'securePassword' -AsPlainText -Force
        $localLogin1Name = "dbatoolscli_localLogin1_$random"
        $localLogin2Name = "dbatoolscli_localLogin2_$random"
        $remoteLoginName = "dbatoolscli_remoteLogin_$random"

        $linkedServer1Name = "dbatoolscli_linkedServer1_$random"
        $linkedServer2Name = "dbatoolscli_linkedServer2_$random"

        New-DbaLogin -SqlInstance $instance2 -Login $localLogin1Name, $localLogin2Name -SecurePassword $securePassword
        New-DbaLogin -SqlInstance $instance3 -Login $remoteLoginName -SecurePassword $securePassword

        $linkedServer1 = New-DbaLinkedServer -SqlInstance $instance2 -LinkedServer $linkedServer1Name -ServerProduct mssql -Provider sqlncli -DataSource $instance3
        $linkedServer2 = New-DbaLinkedServer -SqlInstance $instance2 -LinkedServer $linkedServer2Name -ServerProduct mssql -Provider sqlncli -DataSource $instance3
    }

    AfterAll {
        Remove-DbaLinkedServer -SqlInstance $instance2 -LinkedServer $linkedServer1Name, $linkedServer2Name -Confirm:$false -Force
        Remove-DbaLogin -SqlInstance $instance2 -Login $localLogin1Name, $localLogin2Name -Confirm:$false
        Remove-DbaLogin -SqlInstance $instance3 -Login $remoteLoginName -Confirm:$false
    }

    Context "Command functionality" {
        It "Should return null for an invalid linked server" {
            $results = New-DbaLinkedServerLogin -SqlInstance $instance2 -LinkedServer "dbatoolscli_invalidServer_$random" -LocalLogin $localLogin1Name -RemoteUser $remoteLoginName -RemoteUserPassword $securePassword
            $results | Should -BeNullOrEmpty
        }

        It "Should warn when LinkedServer is not specified" {
            $results = New-DbaLinkedServerLogin -SqlInstance $instance2 -LocalLogin $localLogin1Name -WarningVariable warnings
            $warnings | Should -BeLike "*LinkedServer is required when SqlInstance is specified*"
            $results | Should -BeNullOrEmpty
        }

        It "Creates linked server logins with local login to remote user mapping on two different linked servers" {
            $results = New-DbaLinkedServerLogin -SqlInstance $instance2 -LinkedServer $linkedServer1Name, $linkedServer2Name -LocalLogin $localLogin1Name -RemoteUser $remoteLoginName -RemoteUserPassword $securePassword
            $results.Count | Should -Be 2
            $results.Parent.Name | Should -Be @($linkedServer1Name, $linkedServer2Name)
            $results.Name | Should -Be @($localLogin1Name, $localLogin1Name)
            $results.RemoteUser | Should -Be @($remoteLoginName, $remoteLoginName)
            $results.Impersonate | Should -Be @($false, $false)
        }

        It "Creates a linked server login with impersonation using a linked server from a pipeline" {
            $results = $linkedServer1 | New-DbaLinkedServerLogin -LocalLogin $localLogin2Name -Impersonate
            $results | Should -Not -BeNullOrEmpty
            $results.Parent.Name | Should -Be $linkedServer1Name
            $results.Name | Should -Be $localLogin2Name
            $results.RemoteUser | Should -BeNullOrEmpty
            $results.Impersonate | Should -Be $true
        }

        It "Warns when LocalLogin is not specified" {
            $results = $linkedServer1 | New-DbaLinkedServerLogin -Impersonate -WarningVariable warnings
            $results | Should -BeNullOrEmpty
            $warnings | Should -BeLike "*LocalLogin is required in all scenarios*"
        }
    }
}
