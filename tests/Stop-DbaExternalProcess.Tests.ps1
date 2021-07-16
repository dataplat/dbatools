$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'ComputerName', 'Credential', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Can get a certificate" {
        BeforeAll {
            $null = Add-DbaComputerCertificate -Path $script:appveyorlabrepo\certificates\localhost.crt -Confirm:$false
            $thumbprint = "29C469578D6C6211076A09CEE5C5797EEA0C2713"
        }
        AfterAll {
            Remove-DbaComputerCertificate -Thumbprint $thumbprint -Confirm:$false
        }


    }
}