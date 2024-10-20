param($ModuleName = 'dbatools')

Describe "Backup-DbaComputerCertificate" {
    BeforeDiscovery {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $command = Get-Command Backup-DbaComputerCertificate
        }
        $parms = @(
            'SecurePassword',
            'InputObject',
            'Path',
            'FilePath',
            'Type',
            'EnableException'
        )
        It "Has required parameter: <_>" -ForEach $parms {
            $command | Should -HaveParameter $PSItem
        }
    }

    Context "Certificate is added properly" {
        BeforeAll {
            $null = Add-DbaComputerCertificate -Path $global:appveyorlabrepo\certificates\localhost.crt -Confirm:$false
        }

        AfterAll {
            $null = Remove-DbaComputerCertificate -Thumbprint 29C469578D6C6211076A09CEE5C5797EEA0C2713 -Confirm:$false
        }

        It "returns the proper results" {
            $result = Get-DbaComputerCertificate -Thumbprint 29C469578D6C6211076A09CEE5C5797EEA0C2713 | Backup-DbaComputerCertificate -Path C:\temp
            $result.Name | Should -Match '29C469578D6C6211076A09CEE5C5797EEA0C2713.cer'
        }
    }
}
