#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaLinkedServerLogin",
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
                "RemoteUser",
                "RemoteUserPassword",
                "Impersonate",
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
        $instance2 = Connect-DbaInstance -SqlInstance $TestConfig.instance2
        $instance3 = Connect-DbaInstance -SqlInstance $TestConfig.instance3

        $securePassword = ConvertTo-SecureString -String "securePassword" -AsPlainText -Force
        $localLogin1Name = "dbatoolscli_localLogin1_$random"
        $localLogin2Name = "dbatoolscli_localLogin2_$random"
        $remoteLoginName = "dbatoolscli_remoteLogin_$random"

        $linkedServer1Name = "dbatoolscli_linkedServer1_$random"
        $linkedServer2Name = "dbatoolscli_linkedServer2_$random"

        New-DbaLogin -SqlInstance $instance2 -Login $localLogin1Name, $localLogin2Name -SecurePassword $securePassword
        New-DbaLogin -SqlInstance $instance3 -Login $remoteLoginName -SecurePassword $securePassword

        $linkedServer1 = New-DbaLinkedServer -SqlInstance $instance2 -LinkedServer $linkedServer1Name -ServerProduct mssql -Provider sqlncli -DataSource $instance3
        $linkedServer2 = New-DbaLinkedServer -SqlInstance $instance2 -LinkedServer $linkedServer2Name -ServerProduct mssql -Provider sqlncli -DataSource $instance3

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Remove-DbaLinkedServer -SqlInstance $instance2 -LinkedServer $linkedServer1Name, $linkedServer2Name -Force -ErrorAction SilentlyContinue
        Remove-DbaLogin -SqlInstance $instance2 -Login $localLogin1Name, $localLogin2Name -ErrorAction SilentlyContinue
        Remove-DbaLogin -SqlInstance $instance3 -Login $remoteLoginName -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
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
            $results.Count | Should -Be 2
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