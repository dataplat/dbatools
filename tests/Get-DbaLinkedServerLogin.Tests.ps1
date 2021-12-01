$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'LinkedServer', 'LocalLogin', 'ExcludeLocalLogin', 'InputObject', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should -Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $random = Get-Random
        $instance2 = Connect-DbaInstance -SqlInstance $script:instance2
        $instance3 = Connect-DbaInstance -SqlInstance $script:instance3

        $securePassword = ConvertTo-SecureString -String 's3cur3P4ssw0rd?' -AsPlainText -Force
        $localLogin1Name = "dbatoolscli_localLogin1_$random"
        $localLogin2Name = "dbatoolscli_localLogin2_$random"
        $remoteLoginName = "dbatoolscli_remoteLogin_$random"

        $linkedServer1Name = "dbatoolscli_linkedServer1_$random"
        $linkedServer2Name = "dbatoolscli_linkedServer2_$random"

        New-DbaLogin -SqlInstance $instance2 -Login $localLogin1Name, $localLogin2Name -SecurePassword $securePassword
        New-DbaLogin -SqlInstance $instance3 -Login $remoteLoginName -SecurePassword $securePassword

        $linkedServer1 = New-DbaLinkedServer -SqlInstance $instance2 -LinkedServer $linkedServer1Name -ServerProduct mssql -Provider sqlncli -DataSource $instance3
        $linkedServer2 = New-DbaLinkedServer -SqlInstance $instance2 -LinkedServer $linkedServer2Name -ServerProduct mssql -Provider sqlncli -DataSource $instance3

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
        Remove-DbaLinkedServer -SqlInstance $instance2 -LinkedServer $linkedServer1Name, $linkedServer2Name -Confirm:$false -Force
        Remove-DbaLogin -SqlInstance $instance2 -Login $localLogin1Name, $localLogin2Name -Confirm:$false
        Remove-DbaLogin -SqlInstance $instance3 -Login $remoteLoginName -Confirm:$false
    }

    Context "ensure command works" {

        It "Check the validation for a linked server" {
            $results = Get-DbaLinkedServerLogin -SqlInstance $instance2 -LocalLogin $localLogin1Name -WarningVariable warnings
            $warnings | Should -BeLike "*LinkedServer is required*"
            $results | Should -BeNullOrEmpty
        }

        It "Get a linked server login" {
            $results = Get-DbaLinkedServerLogin -SqlInstance $instance2 -LinkedServer $linkedServer1Name -LocalLogin $localLogin1Name
            $results | Should -Not -BeNullOrEmpty
            $results.Name | Should -Be $localLogin1Name
            $results.RemoteUser | Should -Be $remoteLoginName
            $results.Impersonate | Should -Be $false

            $results = Get-DbaLinkedServerLogin -SqlInstance $instance2 -LinkedServer $linkedServer1Name -LocalLogin $localLogin1Name, $localLogin2Name
            $results.length | Should -Be 2
            $results.Name | Should -Be $localLogin1Name, $localLogin2Name
            $results.RemoteUser | Should -Be $remoteLoginName, $remoteLoginName
            $results.Impersonate | Should -Be $false, $false
        }

        It "Get a linked server login and exclude a login" {
            $results = Get-DbaLinkedServerLogin -SqlInstance $instance2 -LinkedServer $linkedServer1Name -ExcludeLocalLogin $localLogin1Name
            $results | Should -Not -BeNullOrEmpty
            $results.Name | Should -Contain $localLogin2Name
            $results.Name | Should -Not -Contain $localLogin1Name
        }

        It "Get a linked server login by passing in a server via pipeline" {
            $results = $instance2 | Get-DbaLinkedServerLogin -LinkedServer $linkedServer1Name -LocalLogin $localLogin1Name
            $results | Should -Not -BeNullOrEmpty
            $results.Name | Should -Be $localLogin1Name
        }

        It "Get a linked server login by passing in a linked server via pipeline" {
            $results = $linkedServer1 | Get-DbaLinkedServerLogin -LocalLogin $localLogin1Name
            $results | Should -Not -BeNullOrEmpty
            $results.Name | Should -Be $localLogin1Name
        }

        It "Get a linked server login from multiple linked servers" {
            $results = Get-DbaLinkedServerLogin -SqlInstance $instance2 -LinkedServer $linkedServer1Name, $linkedServer2Name -LocalLogin $localLogin1Name
            $results | Should -Not -BeNullOrEmpty
            $results.Name | Should -Be $localLogin1Name, $localLogin1Name
        }
    }
}