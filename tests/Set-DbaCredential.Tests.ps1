#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaCredential",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            # Generated from designed/Set-DbaCredential.json parameters array - exact-match surface law.
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Credential",
                "Identity",
                "SecurePassword",
                "InputObject",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }

        It "Exposes -SecurePassword as a SecureString (secret is write-only, never a plain string)" {
            (Get-Command $CommandName).Parameters["SecurePassword"].ParameterType.Name | Should -Be "SecureString"
        }

        It "Carries the CredentialIdentity alias on -Identity (New-DbaCredential vocabulary)" {
            (Get-Command $CommandName).Parameters["Identity"].Aliases | Should -Contain "CredentialIdentity"
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $random = Get-Random
        $InstanceSingle = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle

        # Two distinct credentials so the multi-record piped leg has independent objects to change.
        $credName1 = "dbatoolsci_cred1_$random"
        $credName2 = "dbatoolsci_cred2_$random"

        $null = New-DbaCredential -SqlInstance $InstanceSingle -Name $credName1 -Identity "olduser1"
        $null = New-DbaCredential -SqlInstance $InstanceSingle -Name $credName2 -Identity "olduser2"

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Remove-DbaCredential -SqlInstance $InstanceSingle -Credential $credName1 -Confirm:$false -ErrorAction SilentlyContinue
        Remove-DbaCredential -SqlInstance $InstanceSingle -Credential $credName2 -Confirm:$false -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "WhatIf support" {
        It "Emits the designed ShouldProcess string and changes nothing" {
            # -WhatIf must show the operation AND leave the credential untouched. WhatIf text is
            # HOST-DIRECT: *>&1 / 6>&1 capture nothing in-process, so a transcript is the reliable
            # in-Pester capture.
            $transcriptPath = Join-Path $TestConfig.Temp "dbatoolsci_whatif_cred_$random.txt"
            $splatWhatIf = @{
                SqlInstance = $InstanceSingle
                Credential  = $credName1
                Identity    = "whatifuser"
                WhatIf      = $true
            }
            try {
                Start-Transcript -Path $transcriptPath
                Set-DbaCredential @splatWhatIf
                Stop-Transcript
                $transcriptText = Get-Content -Path $transcriptPath -Raw
                $expectedTarget = $InstanceSingle.DomainInstanceName
                $expectedAction = "Altering credential $credName1"
                $transcriptText | Should -Match ([regex]::Escape("Performing the operation `"$expectedAction`" on target `"$expectedTarget`""))
            } finally {
                # Stop-Transcript writes to the error stream when the host is no longer transcribing,
                # and Pester counts that as a failure - swallow it in a catch instead.
                try { $null = Stop-Transcript } catch { }
                Remove-Item -Path $transcriptPath -ErrorAction SilentlyContinue
            }

            # ...and the side effect did NOT happen: identity stays olduser1.
            (Get-DbaCredential -SqlInstance $InstanceSingle -Credential $credName1).Identity | Should -Be "olduser1"
        }
    }

    Context "Command behavior" {
        It "Alters the identity via -SqlInstance and decorates like Get-DbaCredential" {
            $splatIdentity = @{
                SqlInstance     = $InstanceSingle
                Credential      = $credName1
                Identity        = "changeduser1"
                EnableException = $true
                Confirm         = $false
            }
            $result = Set-DbaCredential @splatIdentity
            $result.Identity | Should -Be "changeduser1"
            $result.Name | Should -Be $credName1
            # Decoration parity with Get-DbaCredential so Get -> Set -> Get composes.
            $result.ComputerName | Should -Not -BeNullOrEmpty
            $result.InstanceName | Should -Not -BeNullOrEmpty
            $result.SqlInstance | Should -Not -BeNullOrEmpty

            (Get-DbaCredential -SqlInstance $InstanceSingle -Credential $credName1).Identity | Should -Be "changeduser1"
        }

        It "Rotates the secret via -SecurePassword only and preserves the current identity" {
            # A -SecurePassword-only call must re-assert the current identity (the SMO overload dirties
            # Identity so ScriptAlter emits) - the identity must be UNCHANGED afterwards.
            $securePassword = ConvertTo-SecureString "Sup3rStr0ng!Pass$random" -AsPlainText -Force
            $splatSecret = @{
                SqlInstance     = $InstanceSingle
                Credential      = $credName1
                SecurePassword  = $securePassword
                EnableException = $true
                Confirm         = $false
            }
            $result = Set-DbaCredential @splatSecret
            $result.Identity | Should -Be "changeduser1"
            # The secret is write-only and must never surface on the output object.
            ($result.PSObject.Properties.Name -contains "SecurePassword") | Should -Be $false

            (Get-DbaCredential -SqlInstance $InstanceSingle -Credential $credName1).Identity | Should -Be "changeduser1"
        }

        It "Processes multiple piped credentials (N in, N out) and changes each on the server" {
            # Mandatory multi-record piped leg fed by the getCounterpart. Both credentials must come
            # back and both must actually change server-side - read back independently.
            $results = Get-DbaCredential -SqlInstance $InstanceSingle -Credential $credName1, $credName2 |
                Set-DbaCredential -Identity "bulkuser" -Confirm:$false
            ($results | Measure-Object).Count | Should -Be 2
            ($results.Name | Sort-Object -Unique) | Should -Be @($credName1, $credName2 | Sort-Object)

            (Get-DbaCredential -SqlInstance $InstanceSingle -Credential $credName1).Identity | Should -Be "bulkuser"
            (Get-DbaCredential -SqlInstance $InstanceSingle -Credential $credName2).Identity | Should -Be "bulkuser"
        }
    }

    Context "Failure paths" {
        It "Requires either -SqlInstance or an input object" {
            $splatNeither = @{
                Identity        = "orphan"
                Confirm         = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warnNeither"
            }
            $results = Set-DbaCredential @splatNeither
            $warnNeither | Should -BeLike "*You must supply either -SqlInstance or an Input Object*"
            $results | Should -BeNullOrEmpty
        }

        It "Warns and continues when a named credential does not exist on the instance" {
            $splatMissing = @{
                SqlInstance     = $InstanceSingle
                Credential      = "dbatoolsci_nope_$random"
                Identity        = "x"
                Confirm         = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warnMissing"
            }
            $results = Set-DbaCredential @splatMissing
            $warnMissing | Should -BeLike "*does not exist*"
            $results | Should -BeNullOrEmpty
        }

        It "Throws a terminating error on a missing credential with -EnableException" {
            $splatThrow = @{
                SqlInstance     = $InstanceSingle
                Credential      = "dbatoolsci_nope_$random"
                Identity        = "x"
                Confirm         = $false
                EnableException = $true
            }
            { Set-DbaCredential @splatThrow } | Should -Throw
        }
    }
}
