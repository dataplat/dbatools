#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Set-DbaDbCertificate",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            # Generated from designed/Set-DbaDbCertificate.json parameters array - exact-match surface law.
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "ExcludeDatabase",
                "Certificate",
                "Owner",
                "PrivateKeyPath",
                "DecryptionPassword",
                "EncryptionPassword",
                "InputObject",
                "ActiveForServiceBrokerDialog",
                "RemovePrivateKey",
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

        $dbCert = "dbatoolsci_setcert_$random"
        New-DbaDatabase -SqlInstance $InstanceSingle -Name $dbCert

        # A database master key so the certificates can be created with a private key encrypted by
        # the master key - RemovePrivateKey and the two Alter legs all need a real private key present.
        $mkPassword = ConvertTo-SecureString -String "securePassword1!" -AsPlainText -Force
        New-DbaDbMasterKey -SqlInstance $InstanceSingle -Database $dbCert -SecurePassword $mkPassword

        # One certificate per behavioral leg so the tests do not couple through shared state.
        $certToggle = "dbatoolsci_toggle_$random"
        $certOwner = "dbatoolsci_owner_$random"
        $certWhatIf = "dbatoolsci_whatif_$random"
        $certPipe1 = "dbatoolsci_pipe1_$random"
        $certPipe2 = "dbatoolsci_pipe2_$random"
        $certRemoveForce = "dbatoolsci_rmforce_$random"
        $certRemoveNoForce = "dbatoolsci_rmnoforce_$random"
        $allCerts = @($certToggle, $certOwner, $certWhatIf, $certPipe1, $certPipe2, $certRemoveForce, $certRemoveNoForce)

        foreach ($certName in $allCerts) {
            # No -SecurePassword: the private key is encrypted by the database master key.
            New-DbaDbCertificate -SqlInstance $InstanceSingle -Database $dbCert -Name $certName
        }

        # A database principal to hand a certificate to for the owner-change leg.
        $certOwnerPrincipal = "dbatoolsci_certowner_$random"
        Invoke-DbaQuery -SqlInstance $InstanceSingle -Database $dbCert -Query "CREATE USER [$certOwnerPrincipal] WITHOUT LOGIN"

        # New-DbaDbCertificate creates on its OWN connection, so the certificates are invisible on this
        # reused Server object until its cached view is refreshed - the -SqlInstance feeder reads
        # server.Databases[db].Certificates directly.
        $InstanceSingle.Databases[$dbCert].Certificates.Refresh()

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        Remove-DbaDatabase -SqlInstance $InstanceSingle -Database $dbCert -Confirm:$false -ErrorAction SilentlyContinue

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    Context "WhatIf support" {
        It "Emits the designed ShouldProcess string and changes nothing" {
            # The Alter runs against the server, so -WhatIf must gate it and leave the flag untouched.
            # WhatIf text is HOST-DIRECT so a transcript is the reliable capture.
            $transcriptPath = Join-Path $TestConfig.Temp "dbatoolsci_setcertwhatif_$random.txt"
            $splatWhatIf = @{
                SqlInstance                  = $InstanceSingle
                Database                     = $dbCert
                Certificate                  = $certWhatIf
                ActiveForServiceBrokerDialog = $true
                WhatIf                       = $true
            }
            try {
                Start-Transcript -Path $transcriptPath
                Set-DbaDbCertificate @splatWhatIf
                Stop-Transcript
                $transcriptText = Get-Content -Path $transcriptPath -Raw
                $expectedTarget = $InstanceSingle.DomainInstanceName
                $expectedAlter = "Altering certificate '$certWhatIf' in database $dbCert"
                $transcriptText | Should -Match ([regex]::Escape("Performing the operation `"$expectedAlter`" on target `"$expectedTarget`""))
            } finally {
                try { $null = Stop-Transcript } catch { }
                Remove-Item -Path $transcriptPath -ErrorAction SilentlyContinue
            }

            # ...and the side effect did NOT happen: the flag is still off server-side.
            $unchanged = Get-DbaDbCertificate -SqlInstance $InstanceSingle -Database $dbCert -Certificate $certWhatIf
            $unchanged.ActiveForServiceBrokerDialog | Should -BeFalse
        }
    }

    Context "Command behavior" {
        It "Toggles ActiveForServiceBrokerDialog on and off, re-emitting the decorated object" {
            $splatOn = @{
                SqlInstance                  = $InstanceSingle
                Database                     = $dbCert
                Certificate                  = $certToggle
                ActiveForServiceBrokerDialog = $true
                EnableException              = $true
                Confirm                      = $false
            }
            $on = Set-DbaDbCertificate @splatOn
            (Get-DbaDbCertificate -SqlInstance $InstanceSingle -Database $dbCert -Certificate $certToggle).ActiveForServiceBrokerDialog | Should -BeTrue
            # Decoration parity with Get-DbaDbCertificate so Get -> Set -> Get composes.
            $on.ComputerName | Should -Not -BeNullOrEmpty
            $on.InstanceName | Should -Not -BeNullOrEmpty
            $on.SqlInstance | Should -Not -BeNullOrEmpty
            $on.Database | Should -Be $dbCert

            # Tri-state switch: -ActiveForServiceBrokerDialog:$false turns it back off.
            $splatOff = @{
                SqlInstance                  = $InstanceSingle
                Database                     = $dbCert
                Certificate                  = $certToggle
                ActiveForServiceBrokerDialog = $false
                EnableException              = $true
                Confirm                      = $false
            }
            $null = Set-DbaDbCertificate @splatOff
            (Get-DbaDbCertificate -SqlInstance $InstanceSingle -Database $dbCert -Certificate $certToggle).ActiveForServiceBrokerDialog | Should -BeFalse
        }

        It "Changes the certificate owner via Alter()" {
            $splatOwner = @{
                SqlInstance     = $InstanceSingle
                Database        = $dbCert
                Certificate     = $certOwner
                Owner           = $certOwnerPrincipal
                EnableException = $true
                Confirm         = $false
            }
            $null = Set-DbaDbCertificate @splatOwner
            (Get-DbaDbCertificate -SqlInstance $InstanceSingle -Database $dbCert -Certificate $certOwner).Owner | Should -Be $certOwnerPrincipal
        }

        It "Processes multiple piped certificates and resolves each record's own parent (N in, N out)" {
            # Multi-record piped leg. Two distinct certificates piped in must both come back altered,
            # each resolving its own parent database from cert.Parent.
            $results = Get-DbaDbCertificate -SqlInstance $InstanceSingle -Database $dbCert -Certificate $certPipe1, $certPipe2 |
                Set-DbaDbCertificate -ActiveForServiceBrokerDialog -Confirm:$false
            ($results | Measure-Object).Count | Should -Be 2
            ($results.ActiveForServiceBrokerDialog | Sort-Object -Unique) | Should -Be $true

            # Read back independently - each certificate's own flag was set.
            (Get-DbaDbCertificate -SqlInstance $InstanceSingle -Database $dbCert -Certificate $certPipe1).ActiveForServiceBrokerDialog | Should -BeTrue
            (Get-DbaDbCertificate -SqlInstance $InstanceSingle -Database $dbCert -Certificate $certPipe2).ActiveForServiceBrokerDialog | Should -BeTrue
        }

        It "Removes the private key when -Force bypasses ShouldContinue" {
            # Precondition: the certificate has a master-key-encrypted private key.
            (Get-DbaDbCertificate -SqlInstance $InstanceSingle -Database $dbCert -Certificate $certRemoveForce).PrivateKeyEncryptionType | Should -Not -Be "NoKey"
            $splatRemove = @{
                SqlInstance      = $InstanceSingle
                Database         = $dbCert
                Certificate      = $certRemoveForce
                RemovePrivateKey = $true
                Force            = $true
                EnableException  = $true
                Confirm          = $false
            }
            $null = Set-DbaDbCertificate @splatRemove
            (Get-DbaDbCertificate -SqlInstance $InstanceSingle -Database $dbCert -Certificate $certRemoveForce).PrivateKeyEncryptionType | Should -Be "NoKey"
        }
    }

    Context "Failure paths" {
        It "Does not remove the private key without -Force (ShouldContinue is not bypassed by -Confirm)" {
            # ShouldContinue is not governed by -Confirm or preference variables, so non-interactively it
            # cannot be answered and the removal must not happen - which is exactly why -Force exists (#90).
            $splatNoForce = @{
                SqlInstance      = $InstanceSingle
                Database         = $dbCert
                Certificate      = $certRemoveNoForce
                RemovePrivateKey = $true
                Confirm          = $false
            }
            try { Set-DbaDbCertificate @splatNoForce -ErrorAction SilentlyContinue } catch { }
            # The private key is still there - the destructive operation never ran.
            (Get-DbaDbCertificate -SqlInstance $InstanceSingle -Database $dbCert -Certificate $certRemoveNoForce).PrivateKeyEncryptionType | Should -Not -Be "NoKey"
        }

        It "Requires either -SqlInstance or an input object" {
            $splatNeither = @{
                Database                     = $dbCert
                Certificate                  = $certToggle
                ActiveForServiceBrokerDialog = $true
                Confirm                      = $false
                WarningAction                = "SilentlyContinue"
                WarningVariable              = "warnNeither"
            }
            $results = Set-DbaDbCertificate @splatNeither
            $warnNeither | Should -BeLike "*You must supply either -SqlInstance or an Input Object*"
            $results | Should -BeNullOrEmpty
        }

        It "Rejects -RemovePrivateKey together with -PrivateKeyPath" {
            $splatBoth = @{
                SqlInstance      = $InstanceSingle
                Database         = $dbCert
                Certificate      = $certToggle
                RemovePrivateKey = $true
                PrivateKeyPath   = "C:\does\not\matter.pvk"
                Confirm          = $false
                WarningAction    = "SilentlyContinue"
                WarningVariable  = "warnBoth"
            }
            $results = Set-DbaDbCertificate @splatBoth
            $warnBoth | Should -BeLike "*cannot be used together*"
            $results | Should -BeNullOrEmpty
        }

        It "Rejects -PrivateKeyPath without -DecryptionPassword" {
            $splatNoPw = @{
                SqlInstance     = $InstanceSingle
                Database        = $dbCert
                Certificate     = $certToggle
                PrivateKeyPath  = "C:\does\not\matter.pvk"
                Confirm         = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warnNoPw"
            }
            $results = Set-DbaDbCertificate @splatNoPw
            $warnNoPw | Should -BeLike "*-PrivateKeyPath requires -DecryptionPassword*"
            $results | Should -BeNullOrEmpty
        }

        It "Refuses to specify no operation" {
            $splatNoOp = @{
                SqlInstance     = $InstanceSingle
                Database        = $dbCert
                Certificate     = $certToggle
                Confirm         = $false
                WarningAction   = "SilentlyContinue"
                WarningVariable = "warnNoOp"
            }
            $results = Set-DbaDbCertificate @splatNoOp
            $warnNoOp | Should -BeLike "*You must specify at least one operation*"
            $results | Should -BeNullOrEmpty
        }

        It "Throws a terminating error with -EnableException" {
            $splatThrow = @{
                Database                     = $dbCert
                Certificate                  = $certToggle
                ActiveForServiceBrokerDialog = $true
                Confirm                      = $false
                EnableException              = $true
            }
            { Set-DbaDbCertificate @splatThrow } | Should -Throw
        }
    }
}
