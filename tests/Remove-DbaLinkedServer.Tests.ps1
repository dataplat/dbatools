$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'LinkedServer', 'InputObject', 'Force', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $random = Get-Random
        $script:connectedInstance2 = Connect-DbaInstance -SqlInstance $global:TestConfig.instance2
        $script:connectedInstance3 = Connect-DbaInstance -SqlInstance $global:TestConfig.instance3

        $linkedServerName1 = "dbatoolscli_LS1_$random"
        $linkedServerName2 = "dbatoolscli_LS2_$random"
        $linkedServerName3 = "dbatoolscli_LS3_$random"
        $linkedServerName4 = "dbatoolscli_LS4_$random"

        $null = New-DbaLinkedServer -SqlInstance $script:connectedInstance2 -LinkedServer $linkedServerName1
        $null = New-DbaLinkedServer -SqlInstance $script:connectedInstance2 -LinkedServer $linkedServerName2
        $null = New-DbaLinkedServer -SqlInstance $script:connectedInstance2 -LinkedServer $linkedServerName3
        $linkedServer4 = New-DbaLinkedServer -SqlInstance $script:connectedInstance2 -LinkedServer $linkedServerName4

        $securePassword = ConvertTo-SecureString -String 's3cur3P4ssw0rd?' -AsPlainText -Force
        $loginName = "dbatoolscli_test_$random"
        New-DbaLogin -SqlInstance $script:connectedInstance2, $script:connectedInstance3 -Login $loginName -SecurePassword $securePassword

        $newLinkedServerLogin = New-Object Microsoft.SqlServer.Management.Smo.LinkedServerLogin
        $newLinkedServerLogin.Parent = $linkedServer4
        $newLinkedServerLogin.Name = $loginName
        $newLinkedServerLogin.RemoteUser = $loginName
        $newLinkedServerLogin.SetRemotePassword(($securePassword | ConvertFrom-SecurePass))
        $newLinkedServerLogin.Create()
    }
    AfterAll {
        $null = $script:connectedInstance2.Refresh()
        $null = $script:connectedInstance3.Refresh()
        if ($script:connectedInstance2.LinkedServers.Name -contains $linkedServerName1) {
            $script:connectedInstance2.LinkedServers[$linkedServerName1].Drop()
        }

        if ($script:connectedInstance2.LinkedServers.Name -contains $linkedServerName2) {
            $script:connectedInstance2.LinkedServers[$linkedServerName2].Drop()
        }

        if ($script:connectedInstance2.LinkedServers.Name -contains $linkedServerName3) {
            $script:connectedInstance2.LinkedServers[$linkedServerName3].Drop()
        }

        if ($script:connectedInstance2.LinkedServers.Name -contains $linkedServerName4) {
            $script:connectedInstance2.LinkedServers[$linkedServerName4].Drop($true)
        }

        Remove-DbaLogin -SqlInstance $script:connectedInstance2, $script:connectedInstance3 -Login $loginName -Confirm:$false
    }

    Context "ensure command works" {

        It "Removes a linked server" {
            $script:results = Get-DbaLinkedServer -SqlInstance $script:connectedInstance2 -LinkedServer $linkedServerName1
            $script:results.Length | Should -Be 1
            Remove-DbaLinkedServer -SqlInstance $global:TestConfig.instance2 -LinkedServer $linkedServerName1 -Confirm:$false
            $script:results = Get-DbaLinkedServer -SqlInstance $script:connectedInstance2 -LinkedServer $linkedServerName1
            $script:results | Should -BeNullOrEmpty
        }

        It "Tries to remove a non-existent linked server" {
            Remove-DbaLinkedServer -SqlInstance $global:TestConfig.instance2 -LinkedServer $linkedServerName1 -Confirm:$false -WarningVariable warnings
            $warnings | Should -BeLike "*Linked server $linkedServerName1 does not exist on $($script:connectedInstance2.Name)"
        }

        It "Removes a linked server passed in via pipeline" {
            $script:results = Get-DbaLinkedServer -SqlInstance $global:TestConfig.instance2 -LinkedServer $linkedServerName2
            $script:results.Length | Should -Be 1
            Get-DbaLinkedServer -SqlInstance $script:connectedInstance2 -LinkedServer $linkedServerName2 | Remove-DbaLinkedServer -Confirm:$false
            $script:results = Get-DbaLinkedServer -SqlInstance $script:connectedInstance2 -LinkedServer $linkedServerName2
            $script:results | Should -BeNullOrEmpty
        }

        It "Removes a linked server using a server passed in via pipeline" {
            $script:results = Get-DbaLinkedServer -SqlInstance $global:TestConfig.instance2 -LinkedServer $linkedServerName3
            $script:results.Length | Should -Be 1
            $script:connectedInstance2 | Remove-DbaLinkedServer -LinkedServer $linkedServerName3 -Confirm:$false
            $script:results = Get-DbaLinkedServer -SqlInstance $script:connectedInstance2 -LinkedServer $linkedServerName3
            $script:results | Should -BeNullOrEmpty
        }

        It "Tries to remove a linked server that still has logins" {
            Get-DbaLinkedServer -SqlInstance $script:connectedInstance2 -LinkedServer $linkedServerName4 | Remove-DbaLinkedServer -Confirm:$false -WarningVariable warnings
            $warnings | Should -BeLike "*There are still remote logins or linked logins for the server*"
        }

        It "Removes a linked server that requires the -Force param" {
            Get-DbaLinkedServer -SqlInstance $script:connectedInstance2 -LinkedServer $linkedServerName4 | Remove-DbaLinkedServer -Confirm:$false -Force
            $script:results = Get-DbaLinkedServer -SqlInstance $script:connectedInstance2 -LinkedServer $linkedServerName4
            $script:results | Should -BeNullOrEmpty
        }
    }
}