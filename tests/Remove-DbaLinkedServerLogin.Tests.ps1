$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Parameter validation" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'LinkedServer', 'LocalLogin', 'InputObject', 'EnableException'
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
        $localLogin3Name = "dbatoolscli_localLogin3_$random"
        $localLogin4Name = "dbatoolscli_localLogin4_$random"
        $localLogin5Name = "dbatoolscli_localLogin5_$random"
        $localLogin6Name = "dbatoolscli_localLogin6_$random"
        $localLogin7Name = "dbatoolscli_localLogin7_$random"
        $remoteLoginName = "dbatoolscli_remoteLogin_$random"

        $linkedServer1Name = "dbatoolscli_linkedServer1_$random"
        $linkedServer2Name = "dbatoolscli_linkedServer2_$random"

        New-DbaLogin -SqlInstance $instance2 -Login $localLogin1Name, $localLogin2Name, $localLogin3Name, $localLogin4Name, $localLogin5Name, $localLogin6Name, $localLogin7Name -SecurePassword $securePassword
        New-DbaLogin -SqlInstance $instance3 -Login $remoteLoginName -SecurePassword $securePassword

        $linkedServer1 = New-DbaLinkedServer -SqlInstance $instance2 -LinkedServer $linkedServer1Name -ServerProduct mssql -Provider sqlncli -DataSource $instance3
        $linkedServer2 = New-DbaLinkedServer -SqlInstance $instance2 -LinkedServer $linkedServer2Name -ServerProduct mssql -Provider sqlncli -DataSource $instance3

        $linkedServerLogin1 = New-DbaLinkedServerLogin -SqlInstance $instance2 -LinkedServer $linkedServer1Name -LocalLogin $localLogin1Name -RemoteUser $remoteLoginName -RemoteUserPassword $securePassword
        $linkedServerLogin2 = New-DbaLinkedServerLogin -SqlInstance $instance2 -LinkedServer $linkedServer1Name -LocalLogin $localLogin2Name -RemoteUser $remoteLoginName -RemoteUserPassword $securePassword
        $linkedServerLogin3 = New-DbaLinkedServerLogin -SqlInstance $instance2 -LinkedServer $linkedServer1Name -LocalLogin $localLogin3Name -RemoteUser $remoteLoginName -RemoteUserPassword $securePassword
        $linkedServerLogin4 = New-DbaLinkedServerLogin -SqlInstance $instance2 -LinkedServer $linkedServer1Name -LocalLogin $localLogin4Name -RemoteUser $remoteLoginName -RemoteUserPassword $securePassword
        $linkedServerLogin5 = New-DbaLinkedServerLogin -SqlInstance $instance2 -LinkedServer $linkedServer1Name -LocalLogin $localLogin5Name -RemoteUser $remoteLoginName -RemoteUserPassword $securePassword
        $linkedServerLogin6 = New-DbaLinkedServerLogin -SqlInstance $instance2 -LinkedServer $linkedServer1Name -LocalLogin $localLogin6Name -RemoteUser $remoteLoginName -RemoteUserPassword $securePassword
        $linkedServerLogin7 = New-DbaLinkedServerLogin -SqlInstance $instance2 -LinkedServer $linkedServer1Name, $linkedServer2Name -LocalLogin $localLogin7Name -RemoteUser $remoteLoginName -RemoteUserPassword $securePassword
    }
    AfterAll {
        Remove-DbaLinkedServer -SqlInstance $instance2 -LinkedServer $linkedServer1Name, $linkedServer2Name -Confirm:$false -Force
        Remove-DbaLogin -SqlInstance $instance2 -Login $localLogin1Name, $localLogin2Name, $localLogin3Name, $localLogin4Name, $localLogin5Name, $localLogin6Name, $localLogin7Name -Confirm:$false
        Remove-DbaLogin -SqlInstance $instance3 -Login $remoteLoginName -Confirm:$false
    }

    Context "ensure command works" {

        It "Check the validation for a linked server" {
            $results = Remove-DbaLinkedServerLogin -SqlInstance $instance2 -LocalLogin $localLogin1Name -Confirm:$false -WarningVariable WarnVar -WarningAction SilentlyContinue
            $results | Should -BeNullOrEmpty
            $WarnVar | Should -Match "LinkedServer is required"
        }

        It "Remove a linked server login" {
            $results = Get-DbaLinkedServerLogin -SqlInstance $instance2 -LinkedServer $linkedServer1Name -LocalLogin $localLogin1Name
            $results.length | Should -Be 1

            $results = Remove-DbaLinkedServerLogin -SqlInstance $instance2 -LinkedServer $linkedServer1Name -LocalLogin $localLogin1Name -Confirm:$false
            $results = Get-DbaLinkedServerLogin -SqlInstance $instance2 -LinkedServer $linkedServer1Name -LocalLogin $localLogin1Name
            $results | Should -BeNullOrEmpty

            $results = Get-DbaLinkedServerLogin -SqlInstance $instance2 -LinkedServer $linkedServer1Name -LocalLogin $localLogin2Name, $localLogin3Name
            $results.length | Should -Be 2

            $results = Remove-DbaLinkedServerLogin -SqlInstance $instance2 -LinkedServer $linkedServer1Name -LocalLogin $localLogin2Name, $localLogin3Name -Confirm:$false
            $results = Get-DbaLinkedServerLogin -SqlInstance $instance2 -LinkedServer $linkedServer1Name -LocalLogin $localLogin2Name, $localLogin3Name
            $results | Should -BeNullOrEmpty
        }

        It "Remove a linked server login via pipeline with a server instance passed in" {
            $results = $instance2 | Get-DbaLinkedServerLogin -LinkedServer $linkedServer1Name -LocalLogin $localLogin4Name
            $results.length | Should -Be 1

            $results = $instance2 | Remove-DbaLinkedServerLogin -LinkedServer $linkedServer1Name -LocalLogin $localLogin4Name -Confirm:$false
            $results = $instance2 | Get-DbaLinkedServerLogin -LinkedServer $linkedServer1Name -LocalLogin $localLogin4Name
            $results | Should -BeNullOrEmpty
        }

        It "Remove a linked server login via pipeline with a linked server passed in" {
            $results = $linkedServer1 | Get-DbaLinkedServerLogin -LocalLogin $localLogin5Name
            $results.length | Should -Be 1

            $results = $linkedServer1 | Remove-DbaLinkedServerLogin -LocalLogin $localLogin5Name -Confirm:$false
            $results = $linkedServer1 | Get-DbaLinkedServerLogin -LocalLogin $localLogin5Name
            $results | Should -BeNullOrEmpty
        }

        It "Remove a linked server login via pipeline with a linked server login passed in" {
            $results = $linkedServer1 | Get-DbaLinkedServerLogin -LocalLogin $localLogin6Name
            $results.length | Should -Be 1

            $results = $linkedServerLogin6 | Remove-DbaLinkedServerLogin -Confirm:$false
            $results = $linkedServer1 | Get-DbaLinkedServerLogin -LocalLogin $localLogin6Name
            $results | Should -BeNullOrEmpty
        }

        It "Remove linked server logins for multiple linked servers and omit the LocalLogin param" {
            $results = $instance2 | Get-DbaLinkedServerLogin -LinkedServer $linkedServer1Name, $linkedServer2Name
            $results.Parent.Name | Should -Contain $linkedServer1Name
            $results.Parent.Name | Should -Contain $linkedServer2Name
            $results.Name | Should -Contain $localLogin7Name

            $results = $instance2 | Remove-DbaLinkedServerLogin -LinkedServer $linkedServer1Name, $linkedServer2Name -Confirm:$false
            $results = $instance2 | Get-DbaLinkedServerLogin -LinkedServer $linkedServer1Name, $linkedServer2Name
            $results.Name | Should -Not -Contain $localLogin7Name
        }
    }
}