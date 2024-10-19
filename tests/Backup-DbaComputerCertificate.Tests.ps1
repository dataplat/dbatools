param($ModuleName = 'dbatools')

Describe "Backup-DbaComputerCertificate" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Backup-DbaComputerCertificate
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SecurePassword",
                "InputObject",
                "Path",
                "FilePath",
                "Type",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
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
