$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Name', 'ProxyCredential', 'SubSystem', 'Description', 'Login', 'ServerRole', 'MsdbRole', 'Disabled', 'Force', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "verify command works" {
        BeforeAll {
            $random = Get-Random

            $instance2 = Connect-DbaInstance -SqlInstance $script:instance2

            $login = "db$random"
            $plaintext = "BigOlPassword!"
            $password = ConvertTo-SecureString $plaintext -AsPlainText -Force

            $null = Invoke-Command2 -ScriptBlock { net user $login $plaintext /add *>&1 } -ComputerName $instance2.ComputerName
            $credential = New-DbaCredential -SqlInstance $instance2 -Name "dbatoolsci_$random" -Identity "$($instance2.ComputerName)\$login" -Password $password

            $agentProxyAllSubsystems = New-DbaAgentProxy -SqlInstance $instance2 -Name "dbatoolsci_proxy_$random" -Description "Subsystem test" -ProxyCredential "dbatoolsci_$random" -Subsystem PowerShell, AnalysisCommand, AnalysisQuery, CmdExec, Distribution, LogReader, Merge, QueueReader, Snapshot, SSIS

            # ActiveScripting was removed in SQL Server 2016
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
            $results = New-DbaAgentProxy -SqlInstance $instance2 -Name STIG -ProxyCredential 'dbatoolsci_proxytest' -WarningAction SilentlyContinue -WarningVariable warn
            $warn -match 'does not exist' | Should Be $true
        }

        It "validate a proxy with all subsystems" {
            $agentProxyAllSubsystems.Name | Should -Be "dbatoolsci_proxy_$random"
            $agentProxyAllSubsystems.Description | Should -Be "Subsystem test"
            $agentProxyAllSubsystems.CredentialName | Should -Be "dbatoolsci_$random"
            $agentProxyAllSubsystems.CredentialIdentity | Should -Be "$($instance2.ComputerName)\$login"
            $agentProxyAllSubsystems.ComputerName | Should -Be $instance2.ComputerName
            $agentProxyAllSubsystems.InstanceName | Should -Be $instance2.DbaInstanceName
            ($agentProxyAllSubsystems.SubSystems | Where-Object Name -in "PowerShell", "AnalysisCommand", "AnalysisQuery", "CmdExec", "Distribution", "LogReader", "Merge", "QueueReader", "Snapshot", "SSIS").Count | Should -Be 10
            $agentProxyAllSubsystems.IsEnabled | Should -Be $true
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