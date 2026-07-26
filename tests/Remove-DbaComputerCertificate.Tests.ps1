#Requires -Module @{ ModuleName="Pester"; ModuleVersion="5.0" }
param(
    $ModuleName  = "dbatools",
    $CommandName = "Remove-DbaComputerCertificate",
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
                "Thumbprint",
                "Store",
                "Folder",
                "EnableException"
            )
            Compare-Object -ReferenceObject $expectedParameters -DifferenceObject $hasParameters | Should -BeNullOrEmpty
        }
    }
}

Describe $CommandName -Tag IntegrationTests {
    Context "Can remove a certificate" {
        BeforeAll {
            $null = Add-DbaComputerCertificate -Path "$($TestConfig.appveyorlabrepo)\certificates\localhost.crt" -EnableException
            $thumbprint = "29C469578D6C6211076A09CEE5C5797EEA0C2713"
            $results = Remove-DbaComputerCertificate -Thumbprint $thumbprint
        }

        It "returns the store Name" {
            $results.Store | Should -Be "LocalMachine"
        }

        It "returns the folder Name" {
            $results.Folder | Should -Be "My"
        }

        It "reports the proper status of Removed" {
            $results.Status | Should -Be "Removed"
        }

        It "really removed it" {
            $verifyResults = Get-DbaComputerCertificate -Thumbprint $thumbprint
            $verifyResults | Should -BeNullOrEmpty
        }
    }

    Context "Can remove certificates from the property pipeline" {
        BeforeAll {
            $pipelineCertificateSuffix = [guid]::NewGuid().ToString("N")
            $pipelineCertificates = @(
                foreach ($pipelineCertificateNumber in 1..2) {
                    $splatNewPipelineCertificate = @{
                        DnsName           = "dbatools-remove-certificate-$pipelineCertificateNumber-$pipelineCertificateSuffix"
                        CertStoreLocation = "Cert:\LocalMachine\My"
                        NotAfter          = (Get-Date).AddDays(1)
                    }
                    New-SelfSignedCertificate @splatNewPipelineCertificate
                }
            )
            $pipelineCertificateInput = @(
                [pscustomobject]@{
                    Thumbprint = $pipelineCertificates[0].Thumbprint
                }
                [pscustomobject]@{
                    Thumbprint = $pipelineCertificates[1].Thumbprint
                }
            )
            $pipelineResults = @($pipelineCertificateInput | Remove-DbaComputerCertificate -Confirm:$false -EnableException)
        }

        AfterAll {
            foreach ($pipelineCertificate in $pipelineCertificates) {
                $pipelineCertificatePath = "Cert:\LocalMachine\My\$($pipelineCertificate.Thumbprint)"
                if (Test-Path -LiteralPath $pipelineCertificatePath) {
                    $splatRemovePipelineCertificate = @{
                        LiteralPath = $pipelineCertificatePath
                        Force       = $true
                        ErrorAction = "SilentlyContinue"
                    }
                    Remove-Item @splatRemovePipelineCertificate
                }
            }
        }

        It "removes each piped certificate exactly once" {
            @($pipelineResults).Count | Should -Be 2
            foreach ($pipelineCertificate in $pipelineCertificates) {
                @($pipelineResults | Where-Object Thumbprint -eq $pipelineCertificate.Thumbprint).Count | Should -Be 1
            }
            @($pipelineResults | Where-Object Status -ne "Removed") | Should -BeNullOrEmpty
        }

        It "really removed each piped certificate" {
            foreach ($pipelineCertificate in $pipelineCertificates) {
                $pipelineVerifyResults = Get-DbaComputerCertificate -Thumbprint $pipelineCertificate.Thumbprint
                $pipelineVerifyResults | Should -BeNullOrEmpty
            }
        }
    }
}
