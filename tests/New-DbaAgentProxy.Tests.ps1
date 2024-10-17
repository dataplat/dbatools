param($ModuleName = 'dbatools')

Describe "New-DbaAgentProxy" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaAgentProxy
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential
        }
        It "Should have Name as a parameter" {
            $CommandUnderTest | Should -HaveParameter Name -Type String[]
        }
        It "Should have ProxyCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter ProxyCredential -Type String[]
        }
        It "Should have SubSystem as a parameter" {
            $CommandUnderTest | Should -HaveParameter SubSystem -Type String[]
        }
        It "Should have Description as a parameter" {
            $CommandUnderTest | Should -HaveParameter Description -Type String
        }
        It "Should have Login as a parameter" {
            $CommandUnderTest | Should -HaveParameter Login -Type String[]
        }
        It "Should have ServerRole as a parameter" {
            $CommandUnderTest | Should -HaveParameter ServerRole -Type String[]
        }
        It "Should have MsdbRole as a parameter" {
            $CommandUnderTest | Should -HaveParameter MsdbRole -Type String[]
        }
        It "Should have Disabled as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Disabled -Type Switch
        }
        It "Should have Force as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter Force -Type Switch
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch
        }
    }

    Context "Command usage" {
        BeforeDiscovery {
            . (Join-Path $PSScriptRoot 'constants.ps1')
        }

        BeforeAll {
            $random = Get-Random

            $instance2 = Connect-DbaInstance -SqlInstance $global:instance2

            $login = "db$random"
            $plaintext = "BigOlPassword!"
            $password = ConvertTo-SecureString $plaintext -AsPlainText -Force

            $null = Invoke-Command2 -ScriptBlock { net user $login $plaintext /add *>&1 } -ComputerName $instance2.ComputerName
            $credential = New-DbaCredential -SqlInstance $instance2 -Name "dbatoolsci_$random" -Identity "$($instance2.ComputerName)\$login" -Password $password

            $isReplicationInstalled = $instance2.Databases["master"].Query("DECLARE @installed int;BEGIN TRY EXEC @installed = sys.sp_MS_replication_installed; END TRY BEGIN CATCH SET @installed = 0; END CATCH SELECT @installed AS IsReplicationInstalled;").IsReplicationInstalled

            if ($isReplicationInstalled -eq 1) {
                $agentProxyAllSubsystems = New-DbaAgentProxy -SqlInstance $instance2 -Name "dbatoolsci_proxy_$random" -Description "Subsystem test" -ProxyCredential "dbatoolsci_$random" -Subsystem PowerShell, AnalysisCommand, AnalysisQuery, CmdExec, SSIS, Distribution, LogReader, Merge, QueueReader, Snapshot
            } else {
                $agentProxyAllSubsystems = New-DbaAgentProxy -SqlInstance $instance2 -Name "dbatoolsci_proxy_$random" -Description "Subsystem test" -ProxyCredential "dbatoolsci_$random" -Subsystem PowerShell, AnalysisCommand, AnalysisQuery, CmdExec, SSIS
            }

            $agentProxyActiveScripting = New-DbaAgentProxy -SqlInstance $instance2 -Name "dbatoolsci_proxy_ActiveScripting_$random" -Description "ActiveScripting test" -ProxyCredential "dbatoolsci_$random" -Subsystem ActiveScripting

            $agentProxySSISDisabled = New-DbaAgentProxy -SqlInstance $instance2 -Name "dbatoolsci_proxy_SSIS_disabled_$random" -Description "SSIS disabled test" -ProxyCredential "dbatoolsci_$random" -Subsystem SSIS -Disabled

            $loginName = "login_$random"
            $password = 'MyV3ry$ecur3P@ssw0rd'
            $securePassword = ConvertTo-SecureString $password -AsPlainText -Force
            $sqlLogin = New-DbaLogin -SqlInstance $instance2 -Login $loginName -Password $securePassword -Force

            $agentProxyLoginRole = New-DbaAgentProxy -SqlInstance $instance2 -Name "dbatoolsci_proxy_login_role_$random" -ProxyCredential "dbatoolsci_$random" -Login $loginName -SubSystem CmdExec -ServerRole securityadmin -MsdbRole ServerGroupAdministratorRole
        }

        AfterAll {
            $null = Invoke-Command2 -ScriptBlock { net user $args /delete *>&1 } -ArgumentList $login -ComputerName $instance2.ComputerName
            $credential.Drop()
            $sqlLogin.Drop()
            $agentProxyAllSubsystems.Drop()
            $agentProxySSISDisabled.Drop()
            $agentProxyLoginRole.Drop()
        }

        It "does not try to add the proxy without a valid credential" {
            $warn = $null
            $results = New-DbaAgentProxy -SqlInstance $instance2 -Name STIG -ProxyCredential 'dbatoolsci_proxytest' -WarningAction SilentlyContinue -WarningVariable warn
            $warn | Should -Match 'does not exist'
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

        It "validate an ActiveScripting proxy" {
            $agentProxyActiveScripting | Should -BeNullOrEmpty # ActiveScripting was removed in SQL Server 2016
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
