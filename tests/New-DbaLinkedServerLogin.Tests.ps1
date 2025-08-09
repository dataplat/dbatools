$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'LinkedServer', 'LocalLogin', 'RemoteUser', 'RemoteUserPassword', 'Impersonate', 'InputObject', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should -Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $random = Get-Random
        $instance2 = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $instance3 = Connect-DbaInstance -SqlInstance $TestConfig.instance3

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

    Context "ensure command works" {

        It "Check the validation for an invalid linked server" {
            $results = New-DbaLinkedServerLogin -SqlInstance $instance2 -LinkedServer "dbatoolscli_invalidServer_$random" -LocalLogin $localLogin1Name -RemoteUser $remoteLoginName -RemoteUserPassword $securePassword
            $results | Should -BeNullOrEmpty
        }

        It "Check the validation for a linked server" {
            $results = New-DbaLinkedServerLogin -SqlInstance $instance2 -LocalLogin $localLogin1Name -WarningVariable warnings -WarningAction SilentlyContinue
            $warnings | Should -BeLike "*LinkedServer is required when SqlInstance is specified*"
            $results | Should -BeNullOrEmpty
        }

        It "Creates a linked server login with the local login to remote user mapping on two different linked servers" {
            $results = New-DbaLinkedServerLogin -SqlInstance $instance2 -LinkedServer $linkedServer1Name, $linkedServer2Name -LocalLogin $localLogin1Name -RemoteUser $remoteLoginName -RemoteUserPassword $securePassword
            $results.length | Should -Be 2
            $results.Parent.Name | Should -Be $linkedServer1Name, $linkedServer2Name
            $results.Name | Should -Be $localLogin1Name, $localLogin1Name
            $results.RemoteUser | Should -Be $remoteLoginName, $remoteLoginName
            $results.Impersonate | Should -Be $false, $false
        }

        It "Creates a linked server login with impersonation using a linked server from a pipeline" {
            $results = $linkedServer1 | New-DbaLinkedServerLogin -LocalLogin $localLogin2Name -Impersonate
            $results | Should -Not -BeNullOrEmpty
            $results.Parent.Name | Should -Be $linkedServer1Name
            $results.Name | Should -Be $localLogin2Name
            $results.RemoteUser | Should -BeNullOrEmpty
            $results.Impersonate | Should -Be $true
        }

        It "Ensure that LocalLogin is passed in" {
            $results = $linkedServer1 | New-DbaLinkedServerLogin -Impersonate -WarningVariable warnings -WarningAction SilentlyContinue
            $results | Should -BeNullOrEmpty
            $warnings | Should -BeLike "*LocalLogin is required in all scenarios*"
        }
    }
}
