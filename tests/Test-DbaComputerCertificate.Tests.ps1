$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'ComputerName', 'Credential', 'Store', 'Folder', 'Path', 'Thumbprint', 'EnableException', 'Type', 'Threshold'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "tests a certificate" {
        BeforeAll {
            $null = Add-DbaComputerCertificate -Path $script:appveyorlabrepo\certificates\localhost.crt -Confirm:$false -ErrorAction SilentlyContinue
            $thumbprint = "29C469578D6C6211076A09CEE5C5797EEA0C2713"
        }
        AfterAll {
            Remove-DbaComputerCertificate -Thumbprint $thumbprint -Confirm:$false -ErrorAction SilentlyContinue
        }

        It "reports that the certificate is expired" {
            Test-DbaComputerCertificateExpiration -Thumbprint "29C469578D6C6211076A09CEE5C5797EEA0C2713" | Select-Object -ExpandProperty Note | Should -Be "This certificate has expired and is no longer valid"
            $cert.Thumbprint | Should Be $thumbprint
        }
    }
}