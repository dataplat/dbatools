#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Update-DbaServiceAccount",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "ComputerName",
                "Credential",
                "InputObject",
                "ServiceName",
                "Username",
                "ServiceCredential",
                "PreviousPassword",
                "SecurePassword",
                "NoRestart",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    # TODO: This test needs a lot of care
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $login = "winLogin"
        $password = 'MyV3ry$ecur3P@ssw0rd'
        $securePassword = ConvertTo-SecureString $password -AsPlainText -Force
        $newPassword = 'Myxtr33mly$ecur3P@ssw0rd'
        $newSecurePassword = ConvertTo-SecureString $newPassword -AsPlainText -Force
        $server = Connect-DbaInstance -SqlInstance $TestConfig.InstanceRestart
        $computerName = $server.NetName
        $instanceName = $server.ServiceName
        $winLogin = "$computerName\$login"

        #Create Windows login
        $computer = [ADSI]"WinNT://$computerName"
        $user = $computer.Create("user", $login)
        $user.SetPassword($password)
        $user.SetInfo()

        #Get current service users
        $services = Get-DbaService -ComputerName $TestConfig.InstanceRestart -Type Engine, Agent -Instance $instanceName
        $currentAgentUser = ($services | Where-Object { $PSItem.ServiceType -eq "Agent" }).StartName
        $currentEngineUser = ($services | Where-Object { $PSItem.ServiceType -eq "Engine" }).StartName

        # TEST-FIX 2026-07-18 v2c (H's re-strand root-cause + coordinator v2b ruling): the whole
        # set-account-then-revert dance must be ATOMIC per runner. The ACT legs set the engine to
        # .\winLogin; the REVERT legs restore the CAPTURED original by -Username with no
        # -ServiceCredential, which PROMPTS (and THROWS non-interactively) unless that original is
        # a passwordless builtin. v2b guarded only the reverts - so on a domain-account seat the
        # act ran, the revert skipped, and the fixture was STRANDED on winLogin (unstartable after
        # the next restart; H repaired sqldev twice). Fix: ONE gate. If EITHER captured original
        # is not restorable without a credential this runner holds, skip the ENTIRE mutation
        # sequence (Set / Change-password / Change-to-LocalSystem / both reverts) and leave the
        # fixture pristine. The read-only restart-validation context stays live. On a
        # builtin-account seat the full dance runs as before.
        $passwordlessIdentities = @("LocalSystem", "NT AUTHORITY\SYSTEM", "NT AUTHORITY\LOCAL SYSTEM", "NT AUTHORITY\LOCALSERVICE", "NT AUTHORITY\LOCAL SERVICE", "NT AUTHORITY\NETWORKSERVICE", "NT AUTHORITY\NETWORK SERVICE")
        $agentRestorable = ($currentAgentUser -in $passwordlessIdentities -or $currentAgentUser -like "NT Service\*")
        $engineRestorable = ($currentEngineUser -in $passwordlessIdentities -or $currentEngineUser -like "NT Service\*")
        $skipServiceAccountMutation = -not ($agentRestorable -and $engineRestorable)

        #Create a new sysadmin login on SQL Server
        $newLogin = New-Object Microsoft.SqlServer.Management.Smo.Login($server, $winLogin)
        $newLogin.LoginType = "WindowsUser"
        $newLogin.Create()
        $server.Roles["sysadmin"].AddMember($winLogin)
    }

    AfterAll {
        #Cleanup
        $server.Logins[$winLogin].Drop()
        $computer.Delete("User", $login)
    }

    Context "Set new service account for SQL Services" {
        BeforeAll {
            if (-not $skipServiceAccountMutation) {
                $cred = New-Object System.Management.Automation.PSCredential($login, $securePassword)
                $results = Update-DbaServiceAccount -ComputerName $computerName -ServiceName $services.ServiceName -ServiceCredential $cred
            }
        }

        It "Should return something" {
            if ($skipServiceAccountMutation) {
                Set-ItResult -Skipped -Because "runner cannot restore the captured service accounts without a credential it lacks; the whole mutation sequence is skipped so the fixture is never stranded (v2c)"
                return
            }
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should have no warnings" {
            if ($skipServiceAccountMutation) {
                Set-ItResult -Skipped -Because "runner cannot restore the captured service accounts without a credential it lacks; the whole mutation sequence is skipped so the fixture is never stranded (v2c)"
                return
            }
            # TODO: Why does Update-DbaServiceAccount outputs this warning?
            $WarnVar = $WarnVar | Where-Object { $PSItem -notmatch [regex]::Escape('Invalid namespace: root\Microsoft\SQLServer\ReportServer') }
            # TEST-FIX 2026-07-18: the cert-restart ADVISORY is fn-identical and fires wherever a
            # network certificate is configured on the instance (this lab configures one) - same
            # filter pattern as the ReportServer line above.
            $WarnVar = $WarnVar | Where-Object { $PSItem -notmatch "New certificate will not take effect until SQL Server service is restarted" }
            $WarnVar | Should -BeNullOrEmpty
        }

        It "Should be successful" {
            if ($skipServiceAccountMutation) {
                Set-ItResult -Skipped -Because "runner cannot restore the captured service accounts without a credential it lacks; the whole mutation sequence is skipped so the fixture is never stranded (v2c)"
                return
            }
            foreach ($result in $results) {
                $result.Status | Should -Be "Successful"
                $result.State | Should -Be "Running"
                $result.StartName | Should -Be ".\$login"
            }
        }
    }

    Context "Change password of the service account" {
        BeforeAll {
            if (-not $skipServiceAccountMutation) {
                #Change the password
                ([adsi]"WinNT://$computerName/$login,user").SetPassword($newPassword)

                $results = $services | Sort-Object ServicePriority | Update-DbaServiceAccount -Password $newSecurePassword
            }
        }

        It "Password change should return something" {
            if ($skipServiceAccountMutation) {
                Set-ItResult -Skipped -Because "runner cannot restore the captured service accounts without a credential it lacks; the whole mutation sequence is skipped so the fixture is never stranded (v2c)"
                return
            }
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should have no warnings" {
            if ($skipServiceAccountMutation) {
                Set-ItResult -Skipped -Because "runner cannot restore the captured service accounts without a credential it lacks; the whole mutation sequence is skipped so the fixture is never stranded (v2c)"
                return
            }
            # TODO: Why does Update-DbaServiceAccount outputs this warning?
            $WarnVar = $WarnVar | Where-Object { $PSItem -notmatch [regex]::Escape('Invalid namespace: root\Microsoft\SQLServer\ReportServer') }
            # TEST-FIX 2026-07-18: the cert-restart ADVISORY is fn-identical and fires wherever a
            # network certificate is configured on the instance (this lab configures one) - same
            # filter pattern as the ReportServer line above.
            $WarnVar = $WarnVar | Where-Object { $PSItem -notmatch "New certificate will not take effect until SQL Server service is restarted" }
            $WarnVar | Should -BeNullOrEmpty
        }

        It "Should be successful" {
            if ($skipServiceAccountMutation) {
                Set-ItResult -Skipped -Because "runner cannot restore the captured service accounts without a credential it lacks; the whole mutation sequence is skipped so the fixture is never stranded (v2c)"
                return
            }
            foreach ($result in $results) {
                $result.Status | Should -Be "Successful"
                $result.State | Should -Be "Running"
            }
        }
    }

    Context "Service restart validation" {
        BeforeAll {
            $results = Get-DbaService -ComputerName $computerName -ServiceName $services.ServiceName | Restart-DbaService
        }

        It "Service restart should return something" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "Service restart should be successful" {
            foreach ($result in $results) {
                $result.Status | Should -Be "Successful"
                $result.State | Should -Be "Running"
            }
        }
    }

    Context "Change agent service account to local system" {
        BeforeAll {
            if (-not $skipServiceAccountMutation) {
                $results = $services | Where-Object { $PSItem.ServiceType -eq "Agent" } | Update-DbaServiceAccount -Username "NT AUTHORITY\LOCAL SYSTEM"
            }
        }

        It "Should return something" {
            if ($skipServiceAccountMutation) {
                Set-ItResult -Skipped -Because "runner cannot restore the captured service accounts without a credential it lacks; the whole mutation sequence is skipped so the fixture is never stranded (v2c)"
                return
            }
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should have no warnings" {
            if ($skipServiceAccountMutation) {
                Set-ItResult -Skipped -Because "runner cannot restore the captured service accounts without a credential it lacks; the whole mutation sequence is skipped so the fixture is never stranded (v2c)"
                return
            }
            # TODO: Why does Update-DbaServiceAccount outputs this warning?
            $WarnVar = $WarnVar | Where-Object { $PSItem -notmatch [regex]::Escape('Invalid namespace: root\Microsoft\SQLServer\ReportServer') }
            # TEST-FIX 2026-07-18: the cert-restart ADVISORY is fn-identical and fires wherever a
            # network certificate is configured on the instance (this lab configures one) - same
            # filter pattern as the ReportServer line above.
            $WarnVar = $WarnVar | Where-Object { $PSItem -notmatch "New certificate will not take effect until SQL Server service is restarted" }
            $WarnVar | Should -BeNullOrEmpty
        }

        It "Should be successful" {
            if ($skipServiceAccountMutation) {
                Set-ItResult -Skipped -Because "runner cannot restore the captured service accounts without a credential it lacks; the whole mutation sequence is skipped so the fixture is never stranded (v2c)"
                return
            }
            foreach ($result in $results) {
                $result.Status | Should -Be "Successful"
                $result.State | Should -Be "Running"
                $result.StartName | Should -Be "LocalSystem"
            }
        }
    }

    Context "Revert SQL Agent service account changes" {
        BeforeAll {
            if (-not $skipServiceAccountMutation) {
                $results = $services | Where-Object { $PSItem.ServiceType -eq "Agent" } | Update-DbaServiceAccount -Username $currentAgentUser
            }
        }

        It "Should return something" {
            if ($skipServiceAccountMutation) {
                # -Skip evaluates at discovery, before BeforeAll runs - runtime skip instead.
                Set-ItResult -Skipped -Because "the captured original account is a domain identity whose password this runner does not hold (coordinator-approved v2b skip)"
                return
            }
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should have no warnings" {
            if ($skipServiceAccountMutation) {
                # -Skip evaluates at discovery, before BeforeAll runs - runtime skip instead.
                Set-ItResult -Skipped -Because "the captured original account is a domain identity whose password this runner does not hold (coordinator-approved v2b skip)"
                return
            }
            # TODO: Why does Update-DbaServiceAccount outputs this warning?
            $WarnVar = $WarnVar | Where-Object { $PSItem -notmatch [regex]::Escape('Invalid namespace: root\Microsoft\SQLServer\ReportServer') }
            # TEST-FIX 2026-07-18: the cert-restart ADVISORY is fn-identical and fires wherever a
            # network certificate is configured on the instance (this lab configures one) - same
            # filter pattern as the ReportServer line above.
            $WarnVar = $WarnVar | Where-Object { $PSItem -notmatch "New certificate will not take effect until SQL Server service is restarted" }
            $WarnVar | Should -BeNullOrEmpty
        }

        It "Should be successful" {
            if ($skipServiceAccountMutation) {
                # -Skip evaluates at discovery, before BeforeAll runs - runtime skip instead.
                Set-ItResult -Skipped -Because "the captured original account is a domain identity whose password this runner does not hold (coordinator-approved v2b skip)"
                return
            }
            foreach ($result in $results) {
                $result.Status | Should -Be "Successful"
                $result.State | Should -Be "Running"
                $result.StartName | Should -Be $currentAgentUser
            }
        }
    }

    Context "Revert SQL Engine service account changes" {
        BeforeAll {
            if (-not $skipServiceAccountMutation) {
                $results = $services | Where-Object { $PSItem.ServiceType -eq "Engine" } | Update-DbaServiceAccount -Username $currentEngineUser
            }
        }

        It "Should return something" {
            if ($skipServiceAccountMutation) {
                # -Skip evaluates at discovery, before BeforeAll runs - runtime skip instead.
                Set-ItResult -Skipped -Because "the captured original account is a domain identity whose password this runner does not hold (coordinator-approved v2b skip)"
                return
            }
            $results | Should -Not -BeNullOrEmpty
        }

        It "Should have no warnings" {
            if ($skipServiceAccountMutation) {
                # -Skip evaluates at discovery, before BeforeAll runs - runtime skip instead.
                Set-ItResult -Skipped -Because "the captured original account is a domain identity whose password this runner does not hold (coordinator-approved v2b skip)"
                return
            }
            # TODO: Why does Update-DbaServiceAccount outputs this warning?
            $WarnVar = $WarnVar | Where-Object { $PSItem -notmatch [regex]::Escape('Invalid namespace: root\Microsoft\SQLServer\ReportServer') }
            # TEST-FIX 2026-07-18: the cert-restart ADVISORY is fn-identical and fires wherever a
            # network certificate is configured on the instance (this lab configures one) - same
            # filter pattern as the ReportServer line above.
            $WarnVar = $WarnVar | Where-Object { $PSItem -notmatch "New certificate will not take effect until SQL Server service is restarted" }
            $WarnVar | Should -BeNullOrEmpty
        }

        It "Should be successful" {
            if ($skipServiceAccountMutation) {
                # -Skip evaluates at discovery, before BeforeAll runs - runtime skip instead.
                Set-ItResult -Skipped -Because "the captured original account is a domain identity whose password this runner does not hold (coordinator-approved v2b skip)"
                return
            }
            foreach ($result in $results) {
                $result.Status | Should -Be "Successful"
                $result.State | Should -Be "Running"
                $result.StartName | Should -Be $currentEngineUser
            }
        }
    }
}

Describe "$CommandName streaming end-block emission" -Tag IntegrationTests {
    # The end block emits one result per service it finds, then can raise a terminating
    # Stop-Function under -EnableException on a service it cannot find. A buffered end block
    # discards every row already emitted before that throw; a streaming end block preserves
    # them. The live suite above never drives a found-then-not-found batch under
    # -EnableException, so this leg is what proves the streaming end block. It is fully mocked
    # and needs no live service-account fixture.
    Context "When a later service in the batch cannot be found under -EnableException" {
        BeforeAll {
            $computerPart = ([DbaInstanceParameter]$TestConfig.InstanceSingle).ComputerName

            Mock Resolve-DbaNetworkName -ModuleName dbatools -MockWith {
                param($ComputerName, $Credential)
                [PSCustomObject]@{ FullComputerName = "$ComputerName" }
            }

            # The account change itself is a no-op - the row's survival, not the mutation, is under test.
            Mock Invoke-ManagedComputerCommand -ModuleName dbatools -MockWith { }

            # The first service resolves and emits its row; the second is not found, so the
            # source raises its terminating Stop-Function once the first row is already out.
            # A real Get-DbaService object binds to the source's ShouldProcess($serviceObject,
            # $action) call because it ToStrings to a plain string; a PSObject/PSCustomObject does
            # not (the (string, string) overload is unreachable), so a hashtable stand-in is used -
            # it ToStrings cleanly and still exposes the .ServiceType/.ServiceName the source reads.
            Mock Get-DbaService -ModuleName dbatools -MockWith {
                param($ComputerName, $ServiceName, $Credential, $EnableException, $Type, $InstanceName)
                if ($ServiceName -eq "SvcFound") {
                    @{
                        ComputerName = "$ComputerName"
                        ServiceName  = "SvcFound"
                        ServiceType  = "Agent"
                        State        = "Running"
                        StartName    = "NT AUTHORITY\NETWORKSERVICE"
                        InstanceName = "SvcFound"
                    }
                }
                # SvcMissing returns nothing -> the source's "not been found" throw path.
            }

            $emitted = @()
            $threw = $false
            try {
                $splatFoundThenThrow = @{
                    ComputerName    = $computerPart
                    ServiceName     = "SvcFound", "SvcMissing"
                    Username        = "$computerPart\svcuser"
                    SecurePassword  = (ConvertTo-SecureString "P@ssw0rd streaming leg" -AsPlainText -Force)
                    EnableException = $true
                    Confirm         = $false
                }
                Update-DbaServiceAccount @splatFoundThenThrow | ForEach-Object { $emitted += $PSItem }
            } catch {
                $threw = $true
            }
        }

        It "Throws when a later service in the batch cannot be found" {
            $threw | Should -BeTrue
        }

        It "Preserves the row emitted before the throw (streaming, not buffered)" {
            @($emitted).Count | Should -Be 1
            @($emitted)[0].ServiceName | Should -Be "SvcFound"
        }
    }
}