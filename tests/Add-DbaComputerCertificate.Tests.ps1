$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "Certificate is added properly" {
        $results = Add-DbaComputerCertificate -Path $script:appveyorlabrepo\certificates\localhost.crt -Confirm:$false

        It "Should show the proper thumbprint has been added" {
            $results.Thumbprint | Should Be "29C469578D6C6211076A09CEE5C5797EEA0C2713"
        }

        It "Should be in LocalMachine\My Cert Store" {
            $results.PSParentPath | Should Be "Microsoft.PowerShell.Security\Certificate::LocalMachine\My"
        }

        Remove-DbaComputerCertificate -Thumbprint 29C469578D6C6211076A09CEE5C5797EEA0C2713 -Confirm:$false
    }
}