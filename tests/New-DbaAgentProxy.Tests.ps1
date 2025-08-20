#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "New-DbaAgentProxy",
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
                "Name",
                "ProxyCredential",
                "SubSystem",
                "Description",
                "Login",
                "ServerRole",
                "MsdbRole",
                "Disabled",
                "Force",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "verify command works" {
        BeforeAll {
            # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $global:random = Get-Random

            $global:instance2 = Connect-DbaInstance -SqlInstance $TestConfig.instance2

            $global:login = "db$global:random"
            $plaintext = "BigOlPassword!"
            $password = ConvertTo-SecureString $plaintext -AsPlainText -Force

            $null = Invoke-Command2 -ScriptBlock { net user $login $plaintext /add *>&1 } -ComputerName $global:instance2.ComputerName
            $global:credential = New-DbaCredential -SqlInstance $global:instance2 -Name "dbatoolsci_$global:random" -Identity "$($global:instance2.ComputerName)\$global:login" -Password $password

            # if replication is installed then these can be tested also: Distribution, LogReader, Merge, QueueReader, Snapshot
            $global:isReplicationInstalled = $global:instance2.Databases["master"].Query("DECLARE @installed int;BEGIN TRY EXEC @installed = sys.sp_MS_replication_installed; END TRY BEGIN CATCH SET @installed = 0; END CATCH SELECT @installed AS IsReplicationInstalled;").IsReplicationInstalled

            if ($global:isReplicationInstalled -eq 1) {
                $global:agentProxyAllSubsystems = New-DbaAgentProxy -SqlInstance $global:instance2 -Name "dbatoolsci_proxy_$global:random" -Description "Subsystem test" -ProxyCredential "dbatoolsci_$global:random" -Subsystem PowerShell, AnalysisCommand, AnalysisQuery, CmdExec, SSIS, Distribution, LogReader, Merge, QueueReader, Snapshot
            } else {
                $global:agentProxyAllSubsystems = New-DbaAgentProxy -SqlInstance $global:instance2 -Name "dbatoolsci_proxy_$global:random" -Description "Subsystem test" -ProxyCredential "dbatoolsci_$global:random" -Subsystem PowerShell, AnalysisCommand, AnalysisQuery, CmdExec, SSIS
            }

            $global:agentProxySSISDisabled = New-DbaAgentProxy -SqlInstance $global:instance2 -Name "dbatoolsci_proxy_SSIS_disabled_$global:random" -Description "SSIS disabled test" -ProxyCredential "dbatoolsci_$global:random" -Subsystem SSIS -Disabled

            $global:loginName = "login_$global:random"
            $loginPassword = "MyV3ry`$ecur3P@ssw0rd"
            $securePassword = ConvertTo-SecureString $loginPassword -AsPlainText -Force
            $global:sqlLogin = New-DbaLogin -SqlInstance $global:instance2 -Login $global:loginName -Password $securePassword -Force

            $global:agentProxyLoginRole = New-DbaAgentProxy -SqlInstance $global:instance2 -Name "dbatoolsci_proxy_login_role_$global:random" -ProxyCredential "dbatoolsci_$global:random" -Login $global:loginName -SubSystem CmdExec -ServerRole securityadmin -MsdbRole ServerGroupAdministratorRole

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = Invoke-Command2 -ScriptBlock { net user $args /delete *>&1 } -ArgumentList $global:login -ComputerName $global:instance2.ComputerName -ErrorAction SilentlyContinue
            if ($global:credential) { $global:credential.Drop() }
            if ($global:sqlLogin) { $global:sqlLogin.Drop() }
            if ($global:agentProxyAllSubsystems) { $global:agentProxyAllSubsystems.Drop() }
            if ($global:agentProxySSISDisabled) { $global:agentProxySSISDisabled.Drop() }
            if ($global:agentProxyLoginRole) { $global:agentProxyLoginRole.Drop() }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "does not try to add the proxy without a valid credential" {
            $results = New-DbaAgentProxy -SqlInstance $global:instance2 -Name STIG -ProxyCredential "dbatoolsci_proxytest" -WarningAction SilentlyContinue -WarningVariable warn
            $warn -match "does not exist" | Should -Be $true
        }

        It "validate a proxy with all subsystems" {
            $global:agentProxyAllSubsystems.Name | Should -Be "dbatoolsci_proxy_$global:random"
            $global:agentProxyAllSubsystems.Description | Should -Be "Subsystem test"
            $global:agentProxyAllSubsystems.CredentialName | Should -Be "dbatoolsci_$global:random"
            $global:agentProxyAllSubsystems.CredentialIdentity | Should -Be "$($global:instance2.ComputerName)\$global:login"
            $global:agentProxyAllSubsystems.ComputerName | Should -Be $global:instance2.ComputerName
            $global:agentProxyAllSubsystems.InstanceName | Should -Be $global:instance2.DbaInstanceName
            $global:agentProxyAllSubsystems.IsEnabled | Should -Be $true

            if ($global:isReplicationInstalled -eq 1) {
                ($global:agentProxyAllSubsystems.SubSystems | Where-Object Name -in "PowerShell", "AnalysisCommand", "AnalysisQuery", "CmdExec", "SSIS", "Distribution", "LogReader", "Merge", "QueueReader", "Snapshot").Count | Should -Be 10
            } else {
                ($global:agentProxyAllSubsystems.SubSystems | Where-Object Name -in "PowerShell", "AnalysisCommand", "AnalysisQuery", "CmdExec", "SSIS").Count | Should -Be 5
            }
        }

        It "validate a disabled SSIS proxy" {
            $global:agentProxySSISDisabled.Name | Should -Be "dbatoolsci_proxy_SSIS_disabled_$global:random"
            $global:agentProxySSISDisabled.Description | Should -Be "SSIS disabled test"
            $global:agentProxySSISDisabled.CredentialName | Should -Be "dbatoolsci_$global:random"
            $global:agentProxySSISDisabled.CredentialIdentity | Should -Be "$($global:instance2.ComputerName)\$global:login"
            $global:agentProxySSISDisabled.ComputerName | Should -Be $global:instance2.ComputerName
            $global:agentProxySSISDisabled.InstanceName | Should -Be $global:instance2.DbaInstanceName
            $global:agentProxySSISDisabled.SubSystems.Name | Should -Be SSIS
            $global:agentProxySSISDisabled.IsEnabled | Should -Be $false
        }

        It "validate a proxy with a login and roles specified" {
            $global:agentProxyLoginRole.Name | Should -Be "dbatoolsci_proxy_login_role_$global:random"
            $global:agentProxyLoginRole.CredentialName | Should -Be "dbatoolsci_$global:random"
            $global:agentProxyLoginRole.CredentialIdentity | Should -Be "$($global:instance2.ComputerName)\$global:login"
            $global:agentProxyLoginRole.ComputerName | Should -Be $global:instance2.ComputerName
            $global:agentProxyLoginRole.InstanceName | Should -Be $global:instance2.DbaInstanceName
            $global:agentProxyLoginRole.SubSystems.Name | Should -Be CmdExec
            $global:agentProxyLoginRole.Logins.Name | Should -Be $global:loginName
            $global:agentProxyLoginRole.ServerRoles.Name | Should -Be securityadmin
            $global:agentProxyLoginRole.MSDBRoles.Name | Should -Be ServerGroupAdministratorRole
            $global:agentProxyLoginRole.IsEnabled | Should -Be $true
        }
    }
}