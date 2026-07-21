#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaLinkedServerLogin",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            # Generated from designed/Set-DbaLinkedServerLogin.json parameters array - exact-match surface law.
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
        $InstanceSingle = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti1
        $instance3 = Connect-DbaInstance -SqlInstance $TestConfig.InstanceMulti2

        $securePassword = ConvertTo-SecureString -String "securePassword" -AsPlainText -Force
        $localLogin1Name = "dbatoolscli_localLogin1_$random"
        $localLogin2Name = "dbatoolscli_localLogin2_$random"
        $remoteLoginName = "dbatoolscli_remoteLogin_$random"
        $remoteLogin2Name = "dbatoolscli_remoteLogin2_$random"

        $linkedServer1Name = "dbatoolscli_linkedServer1_$random"
        $linkedServer2Name = "dbatoolscli_linkedServer2_$random"

        New-DbaLogin -SqlInstance $InstanceSingle -Login $localLogin1Name, $localLogin2Name -SecurePassword $securePassword
        New-DbaLogin -SqlInstance $instance3 -Login $remoteLoginName, $remoteLogin2Name -SecurePassword $securePassword

        $splatLinkedServer1 = @{
            SqlInstance   = $InstanceSingle
            LinkedServer  = $linkedServer1Name
            ServerProduct = "mssql"
            Provider      = "sqlncli"
            DataSource    = $instance3
        }
        $linkedServer1 = New-DbaLinkedServer @splatLinkedServer1

        $splatLinkedServer2 = @{
            SqlInstance   = $InstanceSingle
            LinkedServer  = $linkedServer2Name
            ServerProduct = "mssql"
            Provider      = "sqlncli"
            DataSource    = $instance3
        }
        $linkedServer2 = New-DbaLinkedServer @splatLinkedServer2

        # localLogin1 is mapped on BOTH linked servers - this is what the multi-record piped test
        # consumes, so each piped record must resolve its OWN parent linked server.
        $splatMapping1 = @{
            SqlInstance        = $InstanceSingle
            LinkedServer       = $linkedServer1Name, $linkedServer2Name
            LocalLogin         = $localLogin1Name
            RemoteUser         = $remoteLoginName
            RemoteUserPassword = $securePassword
        }
        $null = New-DbaLinkedServerLogin @splatMapping1

        # localLogin2 is mapped with -Impersonate on linkedServer1 only - the omitted-switch test.
        $splatMapping2 = @{
            SqlInstance  = $InstanceSingle
            LinkedServer = $linkedServer1Name
            LocalLogin   = $localLogin2Name
            Impersonate  = $true
        }
        $null = New-DbaLinkedServerLogin @splatMapping2

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Remove-DbaLinkedServer -SqlInstance $InstanceSingle -LinkedServer $linkedServer1Name, $linkedServer2Name -Force -ErrorAction SilentlyContinue
        Remove-DbaLogin -SqlInstance $InstanceSingle -Login $localLogin1Name, $localLogin2Name -ErrorAction SilentlyContinue
        Remove-DbaLogin -SqlInstance $instance3 -Login $remoteLoginName, $remoteLogin2Name -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "WhatIf support" {
        It "Emits the designed ShouldProcess string and changes nothing" {
            # WhatIf text is HOST-DIRECT: *>&1 / 6>&1 capture nothing in-process, so a transcript
            # is the reliable in-Pester capture. The asserted string is verbatim from the signed
            # spec's shouldProcessTargets with its placeholders resolved.
            $transcriptPath = Join-Path $TestConfig.Temp "dbatoolsci_whatif_$random.txt"
            $splatWhatIf = @{
                SqlInstance  = $InstanceSingle
                LinkedServer = $linkedServer1Name
                LocalLogin   = $localLogin1Name
                RemoteUser   = $remoteLogin2Name
                WhatIf       = $true
            }
            try {
                Start-Transcript -Path $transcriptPath
                Set-DbaLinkedServerLogin @splatWhatIf
                Stop-Transcript
                $transcriptText = Get-Content -Path $transcriptPath -Raw
                $expectedAction = "Altering linked server login $localLogin1Name on linked server $linkedServer1Name"
                $expectedTarget = $InstanceSingle.DomainInstanceName
                $transcriptText | Should -Match ([regex]::Escape("Performing the operation `"$expectedAction`" on target `"$expectedTarget`""))
            } finally {
                # Stop-Transcript writes to the error stream even under -ErrorAction
                # SilentlyContinue when the host is no longer transcribing, and Pester counts that
                # as a failure - swallow it in a catch instead.
                try { $null = Stop-Transcript } catch { }
                Remove-Item -Path $transcriptPath -ErrorAction SilentlyContinue
            }

            # ...and the side effect did NOT happen.
            $splatUnchanged = @{
                SqlInstance  = $InstanceSingle
                LinkedServer = $linkedServer1Name
                LocalLogin   = $localLogin1Name
            }
            $unchanged = Get-DbaLinkedServerLogin @splatUnchanged
            $unchanged.RemoteUser | Should -Be $remoteLoginName
        }
    }

    Context "Command behavior" {
        It "Alters the remote user via -SqlInstance and re-emits the decorated object" {
            $splatSet = @{
                SqlInstance     = $InstanceSingle
                LinkedServer    = $linkedServer2Name
                LocalLogin      = $localLogin1Name
                RemoteUser      = $remoteLogin2Name
                EnableException = $true
                Confirm         = $false
            }
            $result = Set-DbaLinkedServerLogin @splatSet
            $result.RemoteUser | Should -Be $remoteLogin2Name
            # Decoration parity with Get-DbaLinkedServerLogin so Get -> Set -> Get composes.
            $result.ComputerName | Should -Not -BeNullOrEmpty
            $result.InstanceName | Should -Not -BeNullOrEmpty
            $result.SqlInstance | Should -Not -BeNullOrEmpty
        }

        It "Preserves RemoteUser when only -Impersonate is supplied" {
            # State preservation, the trap this command exists to avoid: Alter re-runs
            # sp_addlinkedsrvlogin, whose omitted clauses RESET rather than leave alone. Changing
            # only Impersonate must still restate @rmtuser, or the mapping's remote user is blanked.
            $splatImpersonateOnly = @{
                SqlInstance     = $InstanceSingle
                LinkedServer    = $linkedServer1Name
                LocalLogin      = $localLogin1Name
                Impersonate     = $false
                EnableException = $true
                Confirm         = $false
            }
            $result = Set-DbaLinkedServerLogin @splatImpersonateOnly
            $result.RemoteUser | Should -Be $remoteLoginName
        }

        It "Never echoes the remote password in output" {
            # SetRemotePassword writes a private field with no getter, so the secret is
            # structurally unreadable - assert no property carries it back.
            $splatSecret = @{
                SqlInstance        = $InstanceSingle
                LinkedServer       = $linkedServer2Name
                LocalLogin         = $localLogin1Name
                RemoteUser         = $remoteLogin2Name
                RemoteUserPassword = $securePassword
                EnableException    = $true
                Confirm            = $false
            }
            $result = Set-DbaLinkedServerLogin @splatSecret
            ($result.PSObject.Properties.Value -join " ") | Should -Not -Match "securePassword"
        }

        It "Leaves Impersonate alone when the switch is not supplied" {
            # THE regression this command is most likely to have: the retired New- sets Impersonate
            # unconditionally, which would silently clear it on every Set- that omitted the switch.
            $splatOmitted = @{
                SqlInstance     = $InstanceSingle
                LinkedServer    = $linkedServer1Name
                LocalLogin      = $localLogin2Name
                EnableException = $true
                Confirm         = $false
            }
            $null = Set-DbaLinkedServerLogin @splatOmitted

            $splatCheck = @{
                SqlInstance  = $InstanceSingle
                LinkedServer = $linkedServer1Name
                LocalLogin   = $localLogin2Name
            }
            (Get-DbaLinkedServerLogin @splatCheck).Impersonate | Should -BeTrue
        }

        It "Turns Impersonate off when explicitly passed -Impersonate:`$false" {
            $splatOff = @{
                SqlInstance     = $InstanceSingle
                LinkedServer    = $linkedServer1Name
                LocalLogin      = $localLogin2Name
                Impersonate     = $false
                EnableException = $true
                Confirm         = $false
            }
            $result = Set-DbaLinkedServerLogin @splatOff
            $result.Impersonate | Should -BeFalse
        }

        It "Processes multiple piped logins and resolves each record's own parent (N in, N out)" {
            # Mandatory multi-record piped leg. Get-DbaLinkedServerLogin carries a deliberate
            # stale-parent carry sentinel; this command must NOT reproduce it, so assert that the
            # two results report the two DISTINCT parent linked servers, not the first one twice.
            $splatGetPair = @{
                SqlInstance  = $InstanceSingle
                LinkedServer = $linkedServer1Name, $linkedServer2Name
                LocalLogin   = $localLogin1Name
            }
            $results = Get-DbaLinkedServerLogin @splatGetPair | Set-DbaLinkedServerLogin -RemoteUser $remoteLoginName -Confirm:$false
            ($results | Measure-Object).Count | Should -Be 2
            ($results.Parent.Name | Sort-Object -Unique) | Should -Be @($linkedServer1Name, $linkedServer2Name | Sort-Object)
        }
    }

    Context "Failure paths" {
        It "Requires either -SqlInstance or an input object" {
            $splatNeither = @{
                LocalLogin      = $localLogin1Name
                RemoteUser      = $remoteLoginName
                Confirm         = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warnNeither"
            }
            $results = Set-DbaLinkedServerLogin @splatNeither
            $warnNeither | Should -BeLike "*You must supply either -SqlInstance or an Input Object*"
            $results | Should -BeNullOrEmpty
        }

        It "Warns and continues on an unknown linked server without -EnableException" {
            $splatWarn = @{
                SqlInstance     = $InstanceSingle
                LinkedServer    = "dbatoolscli_invalidServer_$random", $linkedServer2Name
                LocalLogin      = $localLogin1Name
                RemoteUser      = $remoteLoginName
                Confirm         = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warn"
            }
            $results = Set-DbaLinkedServerLogin @splatWarn
            $warn | Should -Not -BeNullOrEmpty
            ($results | Measure-Object).Count | Should -Be 1
        }

        It "Throws a terminating error with -EnableException" {
            $splatThrow = @{
                SqlInstance     = $InstanceSingle
                LinkedServer    = "dbatoolscli_invalidServer_$random"
                LocalLogin      = $localLogin1Name
                RemoteUser      = $remoteLoginName
                Confirm         = $false
                EnableException = $true
            }
            { Set-DbaLinkedServerLogin @splatThrow } | Should -Throw
        }
    }
}
