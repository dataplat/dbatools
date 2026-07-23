#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaDbEncryptionKey",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            # Generated from designed/Set-DbaDbEncryptionKey.json parameters array - exact-match surface law.
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "ExcludeDatabase",
                "EncryptorName",
                "EncryptionType",
                "EncryptionAlgorithm",
                "InputObject",
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

        # Two freshly created master certificates, both NEVER backed up (LastBackupDate.Year -eq 1):
        #  - encryptCert   is the DEK's initial encryptor (created with -Force so the backup check does
        #    not block DEK creation on an unbacked certificate)
        #  - reencryptCert is the re-encrypt target for the safety-guard and -Force-bypass legs
        $encryptCert = "dbatoolsci_dekcert_$random"
        $reencryptCert = "dbatoolsci_dekrecert_$random"
        $null = New-DbaDbCertificate -SqlInstance $InstanceSingle -Database master -Name $encryptCert
        $null = New-DbaDbCertificate -SqlInstance $InstanceSingle -Database master -Name $reencryptCert

        # Each behavioral leg gets its OWN database so the tests do not couple through shared DEK state.
        $dbRegen = "dbatoolsci_dekregen_$random"
        $dbWhatIf = "dbatoolsci_dekwhatif_$random"
        $dbGuard = "dbatoolsci_dekguard_$random"
        $dbPipe1 = "dbatoolsci_dekpipe1_$random"
        $dbPipe2 = "dbatoolsci_dekpipe2_$random"
        $allDbs = @($dbRegen, $dbWhatIf, $dbGuard, $dbPipe1, $dbPipe2)

        foreach ($dbName in $allDbs) {
            $null = New-DbaDatabase -SqlInstance $InstanceSingle -Name $dbName
            # -Force bypasses the certificate-backup check, letting the DEK be created against the
            # never-backed-up encryptCert. Every DEK starts as Aes256 (New-DbaDbEncryptionKey default).
            $null = New-DbaDbEncryptionKey -SqlInstance $InstanceSingle -Database $dbName -EncryptorName $encryptCert -Force
            # New-DbaDbEncryptionKey creates the key on its own connection, so it is invisible on this
            # reused Server object until the database's SMO view is refreshed.
            $InstanceSingle.Databases[$dbName].Refresh()
        }

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Remove-DbaDatabase -SqlInstance $InstanceSingle -Database $allDbs -Confirm:$false -ErrorAction SilentlyContinue
        Remove-DbaDbCertificate -SqlInstance $InstanceSingle -Database master -Certificate $encryptCert, $reencryptCert -Confirm:$false -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "WhatIf support" {
        It "Emits the designed ShouldProcess string and changes nothing" {
            # Regenerate executes immediately via ExecuteNonQuery, so WhatIf must gate it and leave the
            # server untouched. WhatIf text is HOST-DIRECT so a transcript is the reliable capture.
            $transcriptPath = Join-Path $TestConfig.Temp "dbatoolsci_dekwhatif_$random.txt"
            $splatWhatIf = @{
                SqlInstance         = $InstanceSingle
                Database            = $dbWhatIf
                EncryptionAlgorithm = "Aes192"
                WhatIf              = $true
            }
            try {
                Start-Transcript -Path $transcriptPath
                Set-DbaDbEncryptionKey @splatWhatIf
                Stop-Transcript
                $transcriptText = Get-Content -Path $transcriptPath -Raw
                $expectedTarget = $InstanceSingle.DomainInstanceName
                $expectedRegen = "Regenerating database encryption key in database $dbWhatIf with algorithm Aes192"
                $transcriptText | Should -Match ([regex]::Escape("Performing the operation `"$expectedRegen`" on target `"$expectedTarget`""))
            } finally {
                try { $null = Stop-Transcript } catch { }
                Remove-Item -Path $transcriptPath -ErrorAction SilentlyContinue
            }

            # ...and the side effect did NOT happen: the algorithm is still the Aes256 default.
            $unchanged = Get-DbaDbEncryptionKey -SqlInstance $InstanceSingle -Database $dbWhatIf
            $unchanged.EncryptionAlgorithm | Should -Be "Aes256"
        }
    }

    Context "Command behavior" {
        It "Regenerates the encryption key with a new algorithm and re-emits the decorated object" {
            $splatRegen = @{
                SqlInstance         = $InstanceSingle
                Database            = $dbRegen
                EncryptionAlgorithm = "Aes192"
                EnableException     = $true
                Confirm             = $false
            }
            $result = Set-DbaDbEncryptionKey @splatRegen
            $result.EncryptionAlgorithm | Should -Be "Aes192"
            # Decoration parity with Get-DbaDbEncryptionKey so Get -> Set -> Get composes.
            $result.ComputerName | Should -Not -BeNullOrEmpty
            $result.InstanceName | Should -Not -BeNullOrEmpty
            $result.SqlInstance | Should -Not -BeNullOrEmpty
            $result.Database | Should -Be $dbRegen
            # Read back independently.
            (Get-DbaDbEncryptionKey -SqlInstance $InstanceSingle -Database $dbRegen).EncryptionAlgorithm | Should -Be "Aes192"
        }

        It "Re-encrypts to a new certificate when -Force bypasses the backup check" {
            $splatReencrypt = @{
                SqlInstance     = $InstanceSingle
                Database        = $dbGuard
                EncryptorName   = $reencryptCert
                Force           = $true
                EnableException = $true
                Confirm         = $false
            }
            $result = Set-DbaDbEncryptionKey @splatReencrypt
            $result.EncryptorName | Should -Be $reencryptCert
            (Get-DbaDbEncryptionKey -SqlInstance $InstanceSingle -Database $dbGuard).EncryptorName | Should -Be $reencryptCert
        }

        It "Processes multiple piped encryption keys and resolves each record's own parent (N in, N out)" {
            # Multi-record piped leg. Two distinct encryption keys piped in must both come back altered,
            # each resolving its own parent database.
            $results = Get-DbaDbEncryptionKey -SqlInstance $InstanceSingle -Database $dbPipe1, $dbPipe2 |
                Set-DbaDbEncryptionKey -EncryptionAlgorithm Aes192 -Confirm:$false
            ($results | Measure-Object).Count | Should -Be 2
            ($results.EncryptionAlgorithm | Sort-Object -Unique) | Should -Be "Aes192"
            ($results.Database | Sort-Object) | Should -Be @($dbPipe1, $dbPipe2 | Sort-Object)

            # Read back independently - each database's own key was changed.
            (Get-DbaDbEncryptionKey -SqlInstance $InstanceSingle -Database $dbPipe1).EncryptionAlgorithm | Should -Be "Aes192"
        }
    }

    Context "Failure paths" {
        It "Refuses to re-encrypt to a never-backed-up certificate without -Force" {
            # The backup safety check carries over from New-DbaDbEncryptionKey: re-encrypting to a
            # certificate that has never been backed up is refused, and the key is left untouched.
            $splatGuard = @{
                SqlInstance     = $InstanceSingle
                Database        = $dbWhatIf
                EncryptorName   = $reencryptCert
                Confirm         = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warnGuard"
            }
            $results = Set-DbaDbEncryptionKey @splatGuard
            $warnGuard | Should -BeLike "*has not been backed up*"
            $results | Should -BeNullOrEmpty
            # The encryptor was not changed - it is still the original encryptCert.
            (Get-DbaDbEncryptionKey -SqlInstance $InstanceSingle -Database $dbWhatIf).EncryptorName | Should -Be $encryptCert
        }

        It "Requires either -SqlInstance or an input object" {
            $splatNeither = @{
                Database            = $dbGuard
                EncryptionAlgorithm = "Aes192"
                Confirm             = $false
                WarningAction       = "SilentlyContinue"
                WarningVariable     = "warnNeither"
            }
            $results = Set-DbaDbEncryptionKey @splatNeither
            $warnNeither | Should -BeLike "*You must supply either -SqlInstance or an Input Object*"
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
            $results = Set-DbaDbEncryptionKey @splatNoOp
            $warnNoOp | Should -BeLike "*You must specify at least one operation*"
            $results | Should -BeNullOrEmpty
        }

        It "Throws a terminating error with -EnableException" {
            $splatThrow = @{
                Database            = $dbGuard
                EncryptionAlgorithm = "Aes192"
                Confirm             = $false
                EnableException     = $true
            }
            { Set-DbaDbEncryptionKey @splatThrow } | Should -Throw
        }
    }
}
