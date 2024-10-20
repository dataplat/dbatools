param($ModuleName = 'dbatools')

Describe "Add-DbaComputerCertificate" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $command = Get-Command Add-DbaComputerCertificate
        }
        $paramsList = @(
            'ComputerName',
            'Credential',
            'SecurePassword',
            'Certificate',
            'Path',
            'Store',
            'Folder',
            'Flag',
            'EnableException',
            'WhatIf',
            'Confirm'
        )
        It "Should have parameter: <_>" -ForEach $paramsList {
            $command | Should -HaveParameter $PSItem
        }
    }

    Context "Certificate is added properly" {
        BeforeAll {
            $results = Add-DbaComputerCertificate -Path $global:appveyorlabrepo\certificates\localhost.crt -Confirm:$false
        }

        AfterAll {
            Remove-DbaComputerCertificate -Thumbprint 29C469578D6C6211076A09CEE5C5797EEA0C2713 -Confirm:$false
        }

        It "Should show the proper thumbprint has been added" {
            $results.Thumbprint | Should -Be "29C469578D6C6211076A09CEE5C5797EEA0C2713"
        }

        It "Should be in LocalMachine\My Cert Store" {
            $results.PSParentPath | Should -Be "Microsoft.PowerShell.Security\Certificate::LocalMachine\My"
        }
    }
}
