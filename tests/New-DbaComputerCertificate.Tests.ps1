$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'ComputerName', 'Credential', 'CaServer', 'CaName', 'ClusterInstanceName', 'SecurePassword', 'FriendlyName', 'CertificateTemplate', 'KeyLength', 'Store', 'Folder', 'Dns', 'SelfSigned', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

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
        }
    }
}