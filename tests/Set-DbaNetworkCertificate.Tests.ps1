#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName = "dbatools",
    $CommandName = "Set-DbaNetworkCertificate",
    $PSDefaultParameterValues = $TestConfig.Defaults
)

Describe $CommandName -Tag UnitTests {
    Context "Parameter validation" {
        It "Should have the expected parameters" {
            $hasParameters = (Get-Command $CommandName).Parameters.Values.Name | Where-Object { $PSItem -notin ("WhatIf", "Confirm") }
            $expectedParameters = $TestConfig.CommonParameters
            $expectedParameters += @(
                "SqlInstance",
                "Credential",
                "Certificate",
                "Thumbprint",
                "UnsetCertificate",
                "Force",
                "RestartService",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }

    InModuleScope dbatools {
        Context "RestartService" {
            BeforeEach {
                $script:serviceCredential = New-Object System.Management.Automation.PSCredential(
                    "sql1\svc-sql",
                    (ConvertTo-SecureString "Password123!" -AsPlainText -Force)
                )
                $script:certificateThumbprint = "0123456789ABCDEF0123456789ABCDEF01234567"

                Mock Test-FunctionInterrupt { $false }
                Mock Test-DbaNetworkCertificate {
                    [PSCustomObject]@{
                        ComputerName                    = "sql1"
                        InstanceName                    = "MSSQLSERVER"
                        SqlInstance                     = "sql1"
                        ConfiguredCertificateThumbprint = $null
                        ConfiguredCertificateValid      = $false
                        SuitableCertificateAvailable    = $true
                        SuitableCertificateCount        = 1
                        SuitableCertificates            = [PSCustomObject]@{
                            Thumbprint = $script:certificateThumbprint
                        }
                    }
                }
                Mock Invoke-Command2 {
                    [PSCustomObject]@{
                        Verbose        = @()
                        Exception      = $null
                        ServiceAccount = "sql1\svc-sql"
                    }
                }
                Mock Restart-DbaService { }
            }

            It "passes Credential to Restart-DbaService when RestartService is used" {
                $splatSetNetworkCertificate = @{
                    SqlInstance    = "sql1"
                    Credential     = $script:serviceCredential
                    RestartService = $true
                    Confirm        = $false
                }

                $result = Set-DbaNetworkCertificate @splatSetNetworkCertificate

                $result.CertificateThumbprint | Should -Be $script:certificateThumbprint
                Should -Invoke -CommandName Restart-DbaService -Exactly 1 -Scope It -ModuleName dbatools -ParameterFilter {
                    $SqlInstance.FullName -eq "sql1" -and
                    $Credential -eq $script:serviceCredential -and
                    $Type -eq "Engine" -and
                    $Force -and
                    $EnableException
                }
            }
        }

        Context "Force" {
            BeforeEach {
                $script:certificateThumbprint = "0123456789ABCDEF0123456789ABCDEF01234567"

                Mock Test-FunctionInterrupt { $false }
                Mock Test-DbaNetworkCertificate {
                    if ($Thumbprint) {
                        [PSCustomObject]@{
                            CertificateFound        = $true
                            KeyUsagesValid          = $true
                            DnsNamesValid           = $false
                            PrivateKeyValid         = $true
                            PublicKeyValid          = $true
                            SignatureAlgorithmValid = $false
                            EnhancedKeyUsageValid   = $true
                            ValidityPeriodOk        = $true
                        }
                    } else {
                        [PSCustomObject]@{
                            ComputerName                    = "sql1"
                            InstanceName                    = "MSSQLSERVER"
                            SqlInstance                     = "sql1"
                            ConfiguredCertificateThumbprint = $null
                            ConfiguredCertificateValid      = $false
                            SuitableCertificateAvailable    = $false
                            SuitableCertificateCount        = 0
                            SuitableCertificates            = @()
                        }
                    }
                }
                Mock Invoke-Command2 {
                    [PSCustomObject]@{
                        Verbose        = @()
                        Exception      = $null
                        ServiceAccount = "sql1\svc-sql"
                    }
                }
                Mock Write-Message { }
            }

            It "configures an existing certificate when suitability checks fail and Force is used" {
                $splatSetNetworkCertificate = @{
                    SqlInstance = "sql1"
                    Thumbprint  = $script:certificateThumbprint
                    Force       = $true
                    Confirm     = $false
                }

                $result = Set-DbaNetworkCertificate @splatSetNetworkCertificate

                $result.CertificateThumbprint | Should -Be $script:certificateThumbprint
                Should -Invoke -CommandName Write-Message -Exactly 1 -Scope It -ModuleName dbatools -ParameterFilter {
                    $Level -eq "Warning" -and
                    $Message -match "DnsNamesInvalid, SignatureAlgorithmInvalid"
                }
                Should -Invoke -CommandName Invoke-Command2 -Exactly 1 -Scope It -ModuleName dbatools
            }
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    BeforeAll {
        # We want to run all commands in the BeforeAll block with EnableException to ensure that the test fails if the setup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $computerName = Resolve-DbaComputerName -ComputerName $TestConfig.InstanceRestart -Property ComputerName
        $null = Set-DbaNetworkCertificate -SqlInstance $TestConfig.InstanceRestart -UnsetCertificate -RestartService
        $test = Test-DbaNetworkCertificate -SqlInstance $TestConfig.InstanceRestart
        foreach ($cert in $test.SuitableCertificates) {
            $null = Remove-DbaComputerCertificate -ComputerName $computerName -Thumbprint $cert.Thumbprint
        }

        # We want to run all commands outside of the BeforeAll block without EnableException to be able to test for specific warnings.
        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }

    AfterAll {
        # We want to run all commands in the AfterAll block with EnableException to ensure that the test fails if the cleanup fails.
        $PSDefaultParameterValues["*-Dba*:EnableException"] = $true

        $test = Test-DbaNetworkCertificate -SqlInstance $TestConfig.InstanceRestart
        foreach ($cert in $test.SuitableCertificates) {
            $null = Remove-DbaComputerCertificate -ComputerName $computerName -Thumbprint $cert.Thumbprint
        }

        $PSDefaultParameterValues.Remove("*-Dba*:EnableException")
    }
    It "Warns that no suitable certificate was found" {
        $result = Set-DbaNetworkCertificate -SqlInstance $TestConfig.InstanceRestart -RestartService -WarningAction SilentlyContinue
        $result | Should -BeNullOrEmpty
        $WarnVar | Should -Match "No suitable certificate found"
    }

    It "Creates a first self-signed certificate and applies it" {
        $result = New-DbaComputerCertificate -ComputerName $computerName -SelfSigned | Set-DbaNetworkCertificate -SqlInstance $TestConfig.InstanceRestart -RestartService
        $result.CertificateThumbprint | Should -Not -BeNullOrEmpty
        $WarnVar | Should -BeNullOrEmpty
    }

    It "Creates a second self-signed certificate and applies it" {
        $result = New-DbaComputerCertificate -ComputerName $computerName -SelfSigned | Set-DbaNetworkCertificate -SqlInstance $TestConfig.InstanceRestart -RestartService
        $result.CertificateThumbprint | Should -Not -BeNullOrEmpty
        $WarnVar | Should -BeNullOrEmpty
    }

    It "Does nothing if the certificate is already applied" {
        $result = Set-DbaNetworkCertificate -SqlInstance $TestConfig.InstanceRestart
        $result.CertificateThumbprint | Should -Not -BeNullOrEmpty
        $result.Notes | Should -Be "No changes needed"
        $WarnVar | Should -BeNullOrEmpty
    }

    It "Unsets the certificate" {
        $result = Set-DbaNetworkCertificate -SqlInstance $TestConfig.InstanceRestart -UnsetCertificate -RestartService
        $result.CertificateThumbprint | Should -BeNullOrEmpty
        $WarnVar | Should -BeNullOrEmpty
    }
}
