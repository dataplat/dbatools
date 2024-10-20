$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
$global:TestConfig = Get-TestConfig

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'ComputerName', 'Credential', 'CaServer', 'CaName', 'ClusterInstanceName', 'SecurePassword', 'FriendlyName', 'CertificateTemplate', 'KeyLength', 'Store', 'Folder', 'Flag', 'Dns', 'SelfSigned', 'EnableException', "HashAlgorithm", "MonthsValid"
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

#Tests do not run in appveyor
if (-not $env:appveyor) {
    Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
        Context "Can generate a new certificate" {
            BeforeAll {
                $cert = New-DbaComputerCertificate -SelfSigned -EnableException
            }
            AfterAll {
                Remove-DbaComputerCertificate -Thumbprint $cert.Thumbprint -Confirm:$false
            }
            It "returns the right EnhancedKeyUsageList" {
                "$($cert.EnhancedKeyUsageList)" -match '1\.3\.6\.1\.5\.5\.7\.3\.1' | Should Be $true
            }
            It "returns the right FriendlyName" {
                "$($cert.FriendlyName)" -match 'SQL Server' | Should Be $true
            }
            It "Returns the right default encryption algorithm" {
                "$(($cert |  select-object  @{n="SignatureAlgorithm";e={$_.SignatureAlgorithm.FriendlyName}})).SignatureAlgorithm)" -match 'sha1RSA' | Should Be $true
            }
            It "Returns the right default one year expiry date" {
                $cert.NotAfter  -match ((Get-Date).Date).AddMonths(12) | Should Be $true
            }
        }
    }
}


#Tests do not run in appveyor
if (-not $env:appveyor) {
    Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
        Context "Can generate a new certificate with correct settings" {
            BeforeAll {
                $cert = New-DbaComputerCertificate -SelfSigned -HashAlgorithm "Sha256" -MonthsValid 60 -EnableException
            }
            AfterAll {
                Remove-DbaComputerCertificate -Thumbprint $cert.Thumbprint -Confirm:$false
            }
            It "Returns the right encryption algorithm" {
                "$(($cert |  select-object  @{n="SignatureAlgorithm";e={$_.SignatureAlgorithm.FriendlyName}})).SignatureAlgorithm)" -match 'sha256RSA' | Should Be $true
            }
            It "Returns the right five year (60 month) expiry date" {
                $cert.NotAfter  -match ((Get-Date).Date).AddMonths(60) | Should Be $true
            }
        }
    }
}