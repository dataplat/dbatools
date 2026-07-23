#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaDbMasterKey",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            # Generated from designed/Set-DbaDbMasterKey.json parameters array - exact-match surface law.
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "ExcludeDatabase",
                "InputObject",
                "SecurePassword",
                "Regenerate",
                "AddPasswordEncryption",
                "DropPasswordEncryption",
                "AddServiceKeyEncryption",
                "DropServiceKeyEncryption",
                "Force",
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
        $InstanceSingle = Connect-DbaInstance -SqlInstance $TestConfig.InstanceSingle

        $mkPassword = ConvertTo-SecureString -String "securePassword1!" -AsPlainText -Force

        # Each behavioral leg gets its OWN database so the tests do not couple through shared
        # master-key encryption state.
        $dbWhatIf = "dbatoolsci_mkwhatif_$random"
        $dbToggle = "dbatoolsci_mktoggle_$random"
        $dbGuard = "dbatoolsci_mkguard_$random"
        $dbRegen = "dbatoolsci_mkregen_$random"
        $dbPipe1 = "dbatoolsci_mkpipe1_$random"
        $dbPipe2 = "dbatoolsci_mkpipe2_$random"
        $allDbs = @($dbWhatIf, $dbToggle, $dbGuard, $dbRegen, $dbPipe1, $dbPipe2)

        # Only these two legs need a password-only key (no service-master-key encryptor): the WhatIf leg
        # asserts the service-key encryption was NOT added, and the guard leg needs a key whose only
        # encryptor is the password so that dropping it would be refused. The other databases stay in the
        # SQL default state (encrypted by BOTH the password and the service master key) so their master
        # keys auto-open for the add/regenerate/pipe operations - a password-only key must be opened with
        # its current password before any add/regenerate can decrypt it, which is a server limitation, not
        # the command's job.
        $passwordOnlyDbs = @($dbWhatIf, $dbGuard)

        foreach ($dbName in $allDbs) {
            New-DbaDatabase -SqlInstance $InstanceSingle -Name $dbName
            New-DbaDbMasterKey -SqlInstance $InstanceSingle -Database $dbName -SecurePassword $mkPassword
            # New-DbaDbMasterKey creates the key on its OWN connection, so the master key is invisible
            # on this reused Server object (db.MasterKey stays cached null) - Get- and the command under
            # test both read db.MasterKey, so refresh the database's SMO view before either is exercised.
            $InstanceSingle.Databases[$dbName].Refresh()

            if ($dbName -in $passwordOnlyDbs) {
                # Get- reports IsEncryptedByServer reliably; the drop is raw T-SQL to avoid using the
                # command under test in setup.
                $mk = Get-DbaDbMasterKey -SqlInstance $InstanceSingle -Database $dbName
                if ($mk.IsEncryptedByServer) {
                    Invoke-DbaQuery -SqlInstance $InstanceSingle -Database $dbName -Query "ALTER MASTER KEY DROP ENCRYPTION BY SERVICE MASTER KEY"
                    # The raw T-SQL drop does not update the cached SMO property bag - refresh so
                    # IsEncryptedByServer reflects the normalized (password-only) state for the tests.
                    $InstanceSingle.Databases[$dbName].Refresh()
                }
            }
        }

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Remove-DbaDatabase -SqlInstance $InstanceSingle -Database $allDbs -Confirm:$false -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "WhatIf support" {
        It "Emits BOTH designed ShouldProcess strings and changes nothing" {
            # Two shouldProcessTargets: "Regenerating..." and "Altering encryption...". Every operation
            # executes immediately via ExecuteNonQuery, so WhatIf must gate each and leave the server
            # untouched. WhatIf text is HOST-DIRECT so a transcript is the reliable capture.
            $transcriptPath = Join-Path $TestConfig.Temp "dbatoolsci_mkwhatif_$random.txt"
            $splatWhatIf = @{
                SqlInstance             = $InstanceSingle
                Database                = $dbWhatIf
                Regenerate              = $true
                SecurePassword          = $mkPassword
                AddServiceKeyEncryption = $true
                WhatIf                  = $true
            }
            try {
                Start-Transcript -Path $transcriptPath
                Set-DbaDbMasterKey @splatWhatIf
                Stop-Transcript
                $transcriptText = Get-Content -Path $transcriptPath -Raw
                $expectedTarget = $InstanceSingle.DomainInstanceName
                $expectedRegen = "Regenerating database master key in database $dbWhatIf"
                $expectedAlter = "Altering encryption on database master key in database $dbWhatIf"
                $transcriptText | Should -Match ([regex]::Escape("Performing the operation `"$expectedRegen`" on target `"$expectedTarget`""))
                $transcriptText | Should -Match ([regex]::Escape("Performing the operation `"$expectedAlter`" on target `"$expectedTarget`""))
            } finally {
                try { $null = Stop-Transcript } catch { }
                Remove-Item -Path $transcriptPath -ErrorAction SilentlyContinue
            }

            # ...and the side effect did NOT happen: service-key encryption was never added.
            $unchanged = Get-DbaDbMasterKey -SqlInstance $InstanceSingle -Database $dbWhatIf
            $unchanged.IsEncryptedByServer | Should -BeFalse
        }
    }

    Context "Command behavior" {
        It "Adds and drops service-key encryption, re-emitting the decorated object" {
            $splatAdd = @{
                SqlInstance             = $InstanceSingle
                Database                = $dbToggle
                AddServiceKeyEncryption = $true
                EnableException         = $true
                Confirm                 = $false
            }
            $added = Set-DbaDbMasterKey @splatAdd
            $added.IsEncryptedByServer | Should -BeTrue
            # Decoration parity with Get-DbaDbMasterKey so Get -> Set -> Get composes.
            $added.ComputerName | Should -Not -BeNullOrEmpty
            $added.InstanceName | Should -Not -BeNullOrEmpty
            $added.SqlInstance | Should -Not -BeNullOrEmpty
            $added.Database | Should -Be $dbToggle

            $splatDrop = @{
                SqlInstance              = $InstanceSingle
                Database                 = $dbToggle
                DropServiceKeyEncryption = $true
                EnableException          = $true
                Confirm                  = $false
            }
            $dropped = Set-DbaDbMasterKey @splatDrop
            $dropped.IsEncryptedByServer | Should -BeFalse
        }

        It "Regenerates the master key with a new password" {
            $splatRegen = @{
                SqlInstance     = $InstanceSingle
                Database        = $dbRegen
                Regenerate      = $true
                SecurePassword  = (ConvertTo-SecureString -String "newPassword2!" -AsPlainText -Force)
                EnableException = $true
                Confirm         = $false
            }
            $result = Set-DbaDbMasterKey @splatRegen
            $result | Should -Not -BeNullOrEmpty
            $result.Database | Should -Be $dbRegen
            # The key still resolves after the regenerate.
            Get-DbaDbMasterKey -SqlInstance $InstanceSingle -Database $dbRegen | Should -Not -BeNullOrEmpty
        }

        It "Processes multiple piped master keys and resolves each record's own parent (N in, N out)" {
            # Multi-record piped leg. Two distinct master keys piped in must both come back altered,
            # each resolving its own parent database.
            $results = Get-DbaDbMasterKey -SqlInstance $InstanceSingle -Database $dbPipe1, $dbPipe2 |
                Set-DbaDbMasterKey -AddServiceKeyEncryption -Confirm:$false
            ($results | Measure-Object).Count | Should -Be 2
            ($results.IsEncryptedByServer | Sort-Object -Unique) | Should -Be $true
            ($results.Database | Sort-Object) | Should -Be @($dbPipe1, $dbPipe2 | Sort-Object)

            # Read back independently - each database's own key was changed.
            (Get-DbaDbMasterKey -SqlInstance $InstanceSingle -Database $dbPipe1).IsEncryptedByServer | Should -BeTrue
        }
    }

    Context "Failure paths" {
        It "Requires either -SqlInstance or an input object" {
            $splatNeither = @{
                Database        = $dbGuard
                Regenerate      = $true
                SecurePassword  = $mkPassword
                Confirm         = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warnNeither"
            }
            $results = Set-DbaDbMasterKey @splatNeither
            $warnNeither | Should -BeLike "*You must supply either -SqlInstance or an Input Object*"
            $results | Should -BeNullOrEmpty
        }

        It "Rejects -Force without -Regenerate" {
            $splatForce = @{
                SqlInstance             = $InstanceSingle
                Database                = $dbGuard
                AddServiceKeyEncryption = $true
                Force                   = $true
                Confirm                 = $false
                WarningAction           = "SilentlyContinue"
                WarningVariable         = "warnForce"
            }
            $results = Set-DbaDbMasterKey @splatForce
            $warnForce | Should -BeLike "*-Force is only meaningful with -Regenerate*"
            $results | Should -BeNullOrEmpty
        }

        It "Rejects -Regenerate without -SecurePassword" {
            $splatRegen = @{
                SqlInstance     = $InstanceSingle
                Database        = $dbGuard
                Regenerate      = $true
                Confirm         = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warnRegen"
            }
            $results = Set-DbaDbMasterKey @splatRegen
            $warnRegen | Should -BeLike "*-Regenerate requires -SecurePassword*"
            $results | Should -BeNullOrEmpty
        }

        It "Rejects -AddPasswordEncryption together with -DropPasswordEncryption" {
            $splatBoth = @{
                SqlInstance            = $InstanceSingle
                Database               = $dbGuard
                AddPasswordEncryption  = $mkPassword
                DropPasswordEncryption = $mkPassword
                Confirm                = $false
                WarningAction          = "SilentlyContinue"
                WarningVariable        = "warnBoth"
            }
            $results = Set-DbaDbMasterKey @splatBoth
            $warnBoth | Should -BeLike "*cannot be used together*"
            $results | Should -BeNullOrEmpty
        }

        It "Refuses to specify no operation" {
            $splatNoOp = @{
                SqlInstance     = $InstanceSingle
                Database        = $dbGuard
                Confirm         = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warnNoOp"
            }
            $results = Set-DbaDbMasterKey @splatNoOp
            $warnNoOp | Should -BeLike "*You must specify at least one operation*"
            $results | Should -BeNullOrEmpty
        }

        It "Refuses to drop the last encryptor and continues" {
            # $dbGuard was normalized to password-only (IsEncryptedByServer false). Dropping the
            # password encryption would leave the key with no encryptor - the command must block it,
            # SMO would not.
            $splatGuard = @{
                SqlInstance            = $InstanceSingle
                Database               = $dbGuard
                DropPasswordEncryption = $mkPassword
                Confirm                = $false
                WarningAction          = "SilentlyContinue"
                WarningVariable        = "warnGuard"
            }
            $results = Set-DbaDbMasterKey @splatGuard
            $warnGuard | Should -BeLike "*no encryptor*"
            $results | Should -BeNullOrEmpty
            # The password encryption is still there - the key was not touched.
            (Get-DbaDbMasterKey -SqlInstance $InstanceSingle -Database $dbGuard) | Should -Not -BeNullOrEmpty
        }

        It "Throws a terminating error with -EnableException" {
            $splatThrow = @{
                Database        = $dbGuard
                Regenerate      = $true
                SecurePassword  = $mkPassword
                Confirm         = $false
                EnableException = $true
            }
            { Set-DbaDbMasterKey @splatThrow } | Should -Throw
        }
    }
}
