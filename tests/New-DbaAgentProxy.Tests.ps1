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

            $random = Get-Random

            $instance2 = Connect-DbaInstance -SqlInstance $TestConfig.instance2

            $login = "db$random"
            $plaintext = "BigOlPassword!"
            $password = ConvertTo-SecureString $plaintext -AsPlainText -Force

            $null = Invoke-Command2 -ScriptBlock { net user $login $plaintext /add *>&1 } -ComputerName $instance2.ComputerName
            $credential = New-DbaCredential -SqlInstance $instance2 -Name "dbatoolsci_$random" -Identity "$($instance2.ComputerName)\$login" -Password $password

            # if replication is installed then these can be tested also: Distribution, LogReader, Merge, QueueReader, Snapshot
            $isReplicationInstalled = $instance2.Databases["master"].Query("DECLARE @installed int;BEGIN TRY EXEC @installed = sys.sp_MS_replication_installed; END TRY BEGIN CATCH SET @installed = 0; END CATCH SELECT @installed AS IsReplicationInstalled;").IsReplicationInstalled

            if ($isReplicationInstalled -eq 1) {
                $agentProxyAllSubsystems = New-DbaAgentProxy -SqlInstance $instance2 -Name "dbatoolsci_proxy_$random" -Description "Subsystem test" -ProxyCredential "dbatoolsci_$random" -Subsystem PowerShell, AnalysisCommand, AnalysisQuery, CmdExec, SSIS, Distribution, LogReader, Merge, QueueReader, Snapshot
            } else {
                $agentProxyAllSubsystems = New-DbaAgentProxy -SqlInstance $instance2 -Name "dbatoolsci_proxy_$random" -Description "Subsystem test" -ProxyCredential "dbatoolsci_$random" -Subsystem PowerShell, AnalysisCommand, AnalysisQuery, CmdExec, SSIS
            }

            $agentProxySSISDisabled = New-DbaAgentProxy -SqlInstance $instance2 -Name "dbatoolsci_proxy_SSIS_disabled_$random" -Description "SSIS disabled test" -ProxyCredential "dbatoolsci_$random" -Subsystem SSIS -Disabled

            $loginName = "login_$random"
            $loginPassword = "MyV3ry`$ecur3P@ssw0rd"
            $securePassword = ConvertTo-SecureString $loginPassword -AsPlainText -Force
            $sqlLogin = New-DbaLogin -SqlInstance $instance2 -Login $loginName -Password $securePassword -Force

            $agentProxyLoginRole = New-DbaAgentProxy -SqlInstance $instance2 -Name "dbatoolsci_proxy_login_role_$random" -ProxyCredential "dbatoolsci_$random" -Login $loginName -SubSystem CmdExec -ServerRole securityadmin -MsdbRole ServerGroupAdministratorRole

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $null = Invoke-Command2 -ScriptBlock { net user $args /delete *>&1 } -ArgumentList $login -ComputerName $instance2.ComputerName -ErrorAction SilentlyContinue
            if ($credential) { $credential.Drop() }
            if ($sqlLogin) { $sqlLogin.Drop() }
            if ($agentProxyAllSubsystems) { $agentProxyAllSubsystems.Drop() }
            if ($agentProxySSISDisabled) { $agentProxySSISDisabled.Drop() }
            if ($agentProxyLoginRole) { $agentProxyLoginRole.Drop() }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "does not try to add the proxy without a valid credential" {
            $results = New-DbaAgentProxy -SqlInstance $instance2 -Name STIG -ProxyCredential "dbatoolsci_proxytest" -WarningAction SilentlyContinue -WarningVariable warn
            $warn -match "does not exist" | Should -Be $true
        }

        It "validate a proxy with all subsystems" {
            $agentProxyAllSubsystems.Name | Should -Be "dbatoolsci_proxy_$random"
            $agentProxyAllSubsystems.Description | Should -Be "Subsystem test"
            $agentProxyAllSubsystems.CredentialName | Should -Be "dbatoolsci_$random"
            $agentProxyAllSubsystems.CredentialIdentity | Should -Be "$($instance2.ComputerName)\$login"
            $agentProxyAllSubsystems.ComputerName | Should -Be $instance2.ComputerName
            $agentProxyAllSubsystems.InstanceName | Should -Be $instance2.DbaInstanceName
            $agentProxyAllSubsystems.IsEnabled | Should -Be $true

            if ($isReplicationInstalled -eq 1) {
                ($agentProxyAllSubsystems.SubSystems | Where-Object Name -in "PowerShell", "AnalysisCommand", "AnalysisQuery", "CmdExec", "SSIS", "Distribution", "LogReader", "Merge", "QueueReader", "Snapshot").Count | Should -Be 10
            } else {
                ($agentProxyAllSubsystems.SubSystems | Where-Object Name -in "PowerShell", "AnalysisCommand", "AnalysisQuery", "CmdExec", "SSIS").Count | Should -Be 5
            }
        }

        It "validate a disabled SSIS proxy" {
            $agentProxySSISDisabled.Name | Should -Be "dbatoolsci_proxy_SSIS_disabled_$random"
            $agentProxySSISDisabled.Description | Should -Be "SSIS disabled test"
            $agentProxySSISDisabled.CredentialName | Should -Be "dbatoolsci_$random"
            $agentProxySSISDisabled.CredentialIdentity | Should -Be "$($instance2.ComputerName)\$login"
            $agentProxySSISDisabled.ComputerName | Should -Be $instance2.ComputerName
            $agentProxySSISDisabled.InstanceName | Should -Be $instance2.DbaInstanceName
            $agentProxySSISDisabled.SubSystems.Name | Should -Be SSIS
            $agentProxySSISDisabled.IsEnabled | Should -Be $false
        }

        It "validate a proxy with a login and roles specified" {
            $agentProxyLoginRole.Name | Should -Be "dbatoolsci_proxy_login_role_$random"
            $agentProxyLoginRole.CredentialName | Should -Be "dbatoolsci_$random"
            $agentProxyLoginRole.CredentialIdentity | Should -Be "$($instance2.ComputerName)\$login"
            $agentProxyLoginRole.ComputerName | Should -Be $instance2.ComputerName
            $agentProxyLoginRole.InstanceName | Should -Be $instance2.DbaInstanceName
            $agentProxyLoginRole.SubSystems.Name | Should -Be CmdExec
            $agentProxyLoginRole.Logins.Name | Should -Be $loginName
            $agentProxyLoginRole.ServerRoles.Name | Should -Be securityadmin
            $agentProxyLoginRole.MSDBRoles.Name | Should -Be ServerGroupAdministratorRole
            $agentProxyLoginRole.IsEnabled | Should -Be $true
        }
    }
}