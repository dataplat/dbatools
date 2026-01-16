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

            $InstanceSingle = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle

            $computerName = Resolve-DbaComputerName -ComputerName $TestConfig.InstanceSingle -Property ComputerName
            $userName = "user_$(Get-Random)"
            $password = ConvertTo-SecureString "ThisIsThePassword1" -AsPlainText -Force
            $identity = "$computerName\$userName"
            $proxyName1 = "proxy_$(Get-Random)"
            $proxyName2 = "proxy_$(Get-Random)"
            $proxyName3 = "proxy_$(Get-Random)"

            $splatInvoke = @{
                ComputerName = $computerName
                ScriptBlock  = { New-LocalUser -Name $args[0] -Password $args[1] -Disabled:$false }
                ArgumentList = $userName, $password
            }
            Invoke-Command2 @splatInvoke

            $splatCredential = @{
                SqlInstance = $TestConfig.InstanceSingle
                Name        = $userName
                Identity    = $identity
                Password    = $password
            }
            $null = New-DbaCredential @splatCredential

            # if replication is installed then these can be tested also: Distribution, LogReader, Merge, QueueReader, Snapshot
            $isReplicationInstalled = $InstanceSingle.Databases["master"].Query("DECLARE @installed int;BEGIN TRY EXEC @installed = sys.sp_MS_replication_installed; END TRY BEGIN CATCH SET @installed = 0; END CATCH SELECT @installed AS IsReplicationInstalled;").IsReplicationInstalled

            if ($isReplicationInstalled -eq 1) {
                $agentProxyAllSubsystems = New-DbaAgentProxy -SqlInstance $InstanceSingle -Name $proxyName1 -Description "Subsystem test" -ProxyCredential $userName -Subsystem PowerShell, AnalysisCommand, AnalysisQuery, CmdExec, SSIS, Distribution, LogReader, Merge, QueueReader, Snapshot
            } else {
                $agentProxyAllSubsystems = New-DbaAgentProxy -SqlInstance $InstanceSingle -Name $proxyName1 -Description "Subsystem test" -ProxyCredential $userName -Subsystem PowerShell, AnalysisCommand, AnalysisQuery, CmdExec, SSIS
            }

            $agentProxySSISDisabled = New-DbaAgentProxy -SqlInstance $InstanceSingle -Name $proxyName2 -Description "SSIS disabled test" -ProxyCredential $userName -Subsystem SSIS -Disabled

            $loginName = "login_$random"
            $loginPassword = "MyV3ry`$ecur3P@ssw0rd"
            $securePassword = ConvertTo-SecureString $loginPassword -AsPlainText -Force
            $sqlLogin = New-DbaLogin -SqlInstance $InstanceSingle -Login $loginName -Password $securePassword -Force

            $agentProxyLoginRole = New-DbaAgentProxy -SqlInstance $InstanceSingle -Name $proxyName3 -ProxyCredential $userName -Login $loginName -SubSystem CmdExec -ServerRole securityadmin -MsdbRole ServerGroupAdministratorRole

            # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        AfterAll {
            # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
            $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

            $splatInvoke = @{
                ComputerName = $computerName
                ScriptBlock  = { Remove-LocalUser -Name $args[0] -ErrorAction SilentlyContinue }
                ArgumentList = $userName
            }
            Invoke-Command2 @splatInvoke
            if ($credential) { $credential.Drop() }
            if ($sqlLogin) { $sqlLogin.Drop() }
            if ($agentProxyAllSubsystems) { $agentProxyAllSubsystems.Drop() }
            if ($agentProxySSISDisabled) { $agentProxySSISDisabled.Drop() }
            if ($agentProxyLoginRole) { $agentProxyLoginRole.Drop() }

            $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
        }

        It "does not try to add the proxy without a valid credential" {
            $results = New-DbaAgentProxy -SqlInstance $InstanceSingle -Name STIG -ProxyCredential "dbatoolsci_proxytest" -WarningAction SilentlyContinue -WarningVariable warn
            $warn -match "does not exist" | Should -Be $true
        }

        It "validate a proxy with all subsystems" {
            $agentProxyAllSubsystems.Name | Should -Be $proxyName1
            $agentProxyAllSubsystems.Description | Should -Be "Subsystem test"
            $agentProxyAllSubsystems.CredentialName | Should -Be $userName
            $agentProxyAllSubsystems.CredentialIdentity | Should -Be $identity
            $agentProxyAllSubsystems.ComputerName | Should -Be $InstanceSingle.ComputerName
            $agentProxyAllSubsystems.InstanceName | Should -Be $InstanceSingle.DbaInstanceName
            $agentProxyAllSubsystems.IsEnabled | Should -Be $true

            if ($isReplicationInstalled -eq 1) {
                ($agentProxyAllSubsystems.SubSystems | Where-Object Name -in "PowerShell", "AnalysisCommand", "AnalysisQuery", "CmdExec", "SSIS", "Distribution", "LogReader", "Merge", "QueueReader", "Snapshot").Count | Should -Be 10
            } else {
                ($agentProxyAllSubsystems.SubSystems | Where-Object Name -in "PowerShell", "AnalysisCommand", "AnalysisQuery", "CmdExec", "SSIS").Count | Should -Be 5
            }
        }

        It "validate a disabled SSIS proxy" {
            $agentProxySSISDisabled.Name | Should -Be $proxyName2
            $agentProxySSISDisabled.Description | Should -Be "SSIS disabled test"
            $agentProxySSISDisabled.CredentialName | Should -Be $userName
            $agentProxySSISDisabled.CredentialIdentity | Should -Be $identity
            $agentProxySSISDisabled.ComputerName | Should -Be $InstanceSingle.ComputerName
            $agentProxySSISDisabled.InstanceName | Should -Be $InstanceSingle.DbaInstanceName
            $agentProxySSISDisabled.SubSystems.Name | Should -Be SSIS
            $agentProxySSISDisabled.IsEnabled | Should -Be $false
        }

        It "validate a proxy with a login and roles specified" {
            $agentProxyLoginRole.Name | Should -Be $proxyName3
            $agentProxyLoginRole.CredentialName | Should -Be $userName
            $agentProxyLoginRole.CredentialIdentity | Should -Be $identity
            $agentProxyLoginRole.ComputerName | Should -Be $InstanceSingle.ComputerName
            $agentProxyLoginRole.InstanceName | Should -Be $InstanceSingle.DbaInstanceName
            $agentProxyLoginRole.SubSystems.Name | Should -Be CmdExec
            $agentProxyLoginRole.Logins.Name | Should -Be $loginName
            $agentProxyLoginRole.ServerRoles.Name | Should -Be securityadmin
            $agentProxyLoginRole.MSDBRoles.Name | Should -Be ServerGroupAdministratorRole
            $agentProxyLoginRole.IsEnabled | Should -Be $true
        }
    }
}