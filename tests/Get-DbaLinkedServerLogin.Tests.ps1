#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Get-DbaLinkedServerLogin",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "LinkedServer",
                "LocalLogin",
                "ExcludeLocalLogin",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $random = Get-Random
        $server2 = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1
        $server3 = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti2

        $securePassword = ConvertTo-SecureString -String "s3cur3P4ssw0rd?" -AsPlainText -Force
        $localLogin1Name = "dbatoolscli_localLogin1_$random"
        $localLogin2Name = "dbatoolscli_localLogin2_$random"
        $remoteLoginName = "dbatoolscli_remoteLogin_$random"

        $linkedServer1Name = "dbatoolscli_linkedServer1_$random"
        $linkedServer2Name = "dbatoolscli_linkedServer2_$random"

        $splatLocalLogins = @{
            SqlInstance     = $server2
            Login           = $localLogin1Name, $localLogin2Name
            SecurePassword  = $securePassword
            EnableException = $true
        }
        New-DbaLogin @splatLocalLogins

        $splatRemoteLogin = @{
            SqlInstance     = $server3
            Login           = $remoteLoginName
            SecurePassword  = $securePassword
            EnableException = $true
        }
        New-DbaLogin @splatRemoteLogin

        $splatLinkedServer1 = @{
            SqlInstance     = $server2
            LinkedServer    = $linkedServer1Name
            ServerProduct   = "mssql"
            Provider        = "sqlncli"
            DataSource      = $server3
            EnableException = $true
        }
        $linkedServer1 = New-DbaLinkedServer @splatLinkedServer1

        $splatLinkedServer2 = @{
            SqlInstance     = $server2
            LinkedServer    = $linkedServer2Name
            ServerProduct   = "mssql"
            Provider        = "sqlncli"
            DataSource      = $server3
            EnableException = $true
        }
        $linkedServer2 = New-DbaLinkedServer @splatLinkedServer2

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

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $splatRemoveLinkedServers = @{
            SqlInstance     = $server2
            LinkedServer    = $linkedServer1Name, $linkedServer2Name
            EnableException = $true
            Force           = $true
        }
        Remove-DbaLinkedServer @splatRemoveLinkedServers -ErrorAction SilentlyContinue

        $splatRemoveLocalLogins = @{
            SqlInstance     = $server2
            Login           = $localLogin1Name, $localLogin2Name
            EnableException = $true
        }
        Remove-DbaLogin @splatRemoveLocalLogins -ErrorAction SilentlyContinue

        $splatRemoveRemoteLogin = @{
            SqlInstance     = $server3
            Login           = $remoteLoginName
            EnableException = $true
        }
        Remove-DbaLogin @splatRemoveRemoteLogin -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "When testing linked server login functionality" {

        It "Should validate that LinkedServer is required" {
            $results = Get-DbaLinkedServerLogin -SqlInstance $server2 -LocalLogin $localLogin1Name -WarningVariable warnings 3> $null
            $warnings | Should -BeLike "*LinkedServer is required*"
            $results | Should -BeNullOrEmpty
        }

        It "Should get a linked server login" {
            $results = Get-DbaLinkedServerLogin -SqlInstance $server2 -LinkedServer $linkedServer1Name -LocalLogin $localLogin1Name
            $results | Should -Not -BeNullOrEmpty
            $results.Name | Should -Be $localLogin1Name
            $results.RemoteUser | Should -Be $remoteLoginName
            $results.Impersonate | Should -Be $false

            $results = Get-DbaLinkedServerLogin -SqlInstance $server2 -LinkedServer $linkedServer1Name -LocalLogin $localLogin1Name, $localLogin2Name
            $results.Count | Should -Be 2
            $results.Name | Should -Be $localLogin1Name, $localLogin2Name
            $results.RemoteUser | Should -Be $remoteLoginName, $remoteLoginName
            $results.Impersonate | Should -Be $false, $false
        }

        It "Should get a linked server login and exclude a login" {
            $results = Get-DbaLinkedServerLogin -SqlInstance $server2 -LinkedServer $linkedServer1Name -ExcludeLocalLogin $localLogin1Name
            $results | Should -Not -BeNullOrEmpty
            $results.Name | Should -Contain $localLogin2Name
            $results.Name | Should -Not -Contain $localLogin1Name
        }

        It "Should get a linked server login by passing in a server via pipeline" {
            $results = $server2 | Get-DbaLinkedServerLogin -LinkedServer $linkedServer1Name -LocalLogin $localLogin1Name
            $results | Should -Not -BeNullOrEmpty
            $results.Name | Should -Be $localLogin1Name
        }

        It "Should get a linked server login by passing in a linked server via pipeline" {
            $results = $linkedServer1 | Get-DbaLinkedServerLogin -LocalLogin $localLogin1Name
            $results | Should -Not -BeNullOrEmpty
            $results.Name | Should -Be $localLogin1Name
        }

        It "Should get a linked server login from multiple linked servers" {
            $results = Get-DbaLinkedServerLogin -SqlInstance $server2 -LinkedServer $linkedServer1Name, $linkedServer2Name -LocalLogin $localLogin1Name
            $results | Should -Not -BeNullOrEmpty
            $results.Name | Should -Be $localLogin1Name, $localLogin1Name
        }

        It "Returns output of the documented type" {
            $result = Get-DbaLinkedServerLogin -SqlInstance $server2 -LinkedServer $linkedServer1Name -LocalLogin $localLogin1Name
            $result | Should -Not -BeNullOrEmpty
            $result[0].psobject.TypeNames | Should -Contain "Microsoft.SqlServer.Management.Smo.LinkedServerLogin"
        }

        It "Has the expected default display properties" {
            $result = Get-DbaLinkedServerLogin -SqlInstance $server2 -LinkedServer $linkedServer1Name -LocalLogin $localLogin1Name
            $defaultProps = $result[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames
            $expectedDefaults = @("ComputerName", "InstanceName", "SqlInstance", "Name", "RemoteUser", "Impersonate")
            foreach ($prop in $expectedDefaults) {
                $defaultProps | Should -Contain $prop -Because "property '$prop' should be in the default display set"
            }
        }
    }
}