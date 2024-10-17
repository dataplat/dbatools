param($ModuleName = 'dbatools')

Describe "Get-DbaLinkedServerLogin" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"

        $random = Get-Random
        $server2 = Connect-DbaInstance -SqlInstance $script:instance2
        $server3 = Connect-DbaInstance -SqlInstance $script:instance3

        $securePassword = ConvertTo-SecureString -String 's3cur3P4ssw0rd?' -AsPlainText -Force
        $localLogin1Name = "dbatoolscli_localLogin1_$random"
        $localLogin2Name = "dbatoolscli_localLogin2_$random"
        $remoteLoginName = "dbatoolscli_remoteLogin_$random"

        $linkedServer1Name = "dbatoolscli_linkedServer1_$random"
        $linkedServer2Name = "dbatoolscli_linkedServer2_$random"

        New-DbaLogin -SqlInstance $server2 -Login $localLogin1Name, $localLogin2Name -SecurePassword $securePassword
        New-DbaLogin -SqlInstance $server3 -Login $remoteLoginName -SecurePassword $securePassword

        $linkedServer1 = New-DbaLinkedServer -SqlInstance $server2 -LinkedServer $linkedServer1Name -ServerProduct mssql -Provider sqlncli -DataSource $server3
        $linkedServer2 = New-DbaLinkedServer -SqlInstance $server2 -LinkedServer $linkedServer2Name -ServerProduct mssql -Provider sqlncli -DataSource $server3

        $newLinkedServerLogin1 = New-Object Microsoft.SqlServer.Management.Smo.LinkedServerLogin
        $newLinkedServerLogin1.Parent = $linkedServer1
        $newLinkedServerLogin1.Name = $localLogin1Name
        $newLinkedServerLogin1.RemoteUser = $remoteLoginName
        $newLinkedServerLogin1.Impersonate = $false
        $newLinkedServerLogin1.SetRemotePassword(($securePassword | ConvertFrom-SecurePass))
        $newLinkedServerLogin1.Create()

        $newLinkedServerLogin2 = New-Object Microsoft.SqlServer.Management.Smo.LinkedServerLogin
        $newLinkedServerLogin2.Parent = $linkedServer1
        $newLinkedServerLogin2.Name = $localLogin2Name
        $newLinkedServerLogin2.RemoteUser = $remoteLoginName
        $newLinkedServerLogin2.Impersonate = $false
        $newLinkedServerLogin2.SetRemotePassword(($securePassword | ConvertFrom-SecurePass))
        $newLinkedServerLogin2.Create()

        $newLinkedServerLogin3 = New-Object Microsoft.SqlServer.Management.Smo.LinkedServerLogin
        $newLinkedServerLogin3.Parent = $linkedServer2
        $newLinkedServerLogin3.Name = $localLogin1Name
        $newLinkedServerLogin3.RemoteUser = $remoteLoginName
        $newLinkedServerLogin3.Impersonate = $false
        $newLinkedServerLogin3.SetRemotePassword(($securePassword | ConvertFrom-SecurePass))
        $newLinkedServerLogin3.Create()
    }

    AfterAll {
        Remove-DbaLinkedServer -SqlInstance $server2 -LinkedServer $linkedServer1Name, $linkedServer2Name -Confirm:$false -Force
        Remove-DbaLogin -SqlInstance $server2 -Login $localLogin1Name, $localLogin2Name -Confirm:$false
        Remove-DbaLogin -SqlInstance $server3 -Login $remoteLoginName -Confirm:$false
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaLinkedServerLogin
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Not -Mandatory
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Not -Mandatory
        }
        It "Should have LinkedServer as a parameter" {
            $CommandUnderTest | Should -HaveParameter LinkedServer -Type String[] -Not -Mandatory
        }
        It "Should have LocalLogin as a parameter" {
            $CommandUnderTest | Should -HaveParameter LocalLogin -Type String[] -Not -Mandatory
        }
        It "Should have ExcludeLocalLogin as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeLocalLogin -Type String[] -Not -Mandatory
        }
        It "Should have InputObject as a parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Object[] -Not -Mandatory
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type SwitchParameter -Not -Mandatory
        }
    }

    Context "Command usage" {
        It "Check the validation for a linked server" {
            $warnings = @()
            $results = Get-DbaLinkedServerLogin -SqlInstance $server2 -LocalLogin $localLogin1Name -WarningVariable warnings 3> $null
            $warnings | Should -BeLike "*LinkedServer is required*"
            $results | Should -BeNullOrEmpty
        }

        It "Get a linked server login" {
            $results = Get-DbaLinkedServerLogin -SqlInstance $server2 -LinkedServer $linkedServer1Name -LocalLogin $localLogin1Name
            $results | Should -Not -BeNullOrEmpty
            $results.Name | Should -Be $localLogin1Name
            $results.RemoteUser | Should -Be $remoteLoginName
            $results.Impersonate | Should -Be $false

            $results = Get-DbaLinkedServerLogin -SqlInstance $server2 -LinkedServer $linkedServer1Name -LocalLogin $localLogin1Name, $localLogin2Name
            $results.length | Should -Be 2
            $results.Name | Should -Be $localLogin1Name, $localLogin2Name
            $results.RemoteUser | Should -Be $remoteLoginName, $remoteLoginName
            $results.Impersonate | Should -Be $false, $false
        }

        It "Get a linked server login and exclude a login" {
            $results = Get-DbaLinkedServerLogin -SqlInstance $server2 -LinkedServer $linkedServer1Name -ExcludeLocalLogin $localLogin1Name
            $results | Should -Not -BeNullOrEmpty
            $results.Name | Should -Contain $localLogin2Name
            $results.Name | Should -Not -Contain $localLogin1Name
        }

        It "Get a linked server login by passing in a server via pipeline" {
            $results = $server2 | Get-DbaLinkedServerLogin -LinkedServer $linkedServer1Name -LocalLogin $localLogin1Name
            $results | Should -Not -BeNullOrEmpty
            $results.Name | Should -Be $localLogin1Name
        }

        It "Get a linked server login by passing in a linked server via pipeline" {
            $results = $linkedServer1 | Get-DbaLinkedServerLogin -LocalLogin $localLogin1Name
            $results | Should -Not -BeNullOrEmpty
            $results.Name | Should -Be $localLogin1Name
        }

        It "Get a linked server login from multiple linked servers" {
            $results = Get-DbaLinkedServerLogin -SqlInstance $server2 -LinkedServer $linkedServer1Name, $linkedServer2Name -LocalLogin $localLogin1Name
            $results | Should -Not -BeNullOrEmpty
            $results.Name | Should -Be $localLogin1Name, $localLogin1Name
        }
    }
}
