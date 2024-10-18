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
        It "Should have SecurePassword as a non-mandatory SecureString parameter" {
            $CommandUnderTest | Should -HaveParameter SecurePassword -Type SecureString -Mandatory:$false
        }
        It "Should have InputObject as a non-mandatory System.Object[] parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type System.Object[] -Mandatory:$false
        }
        It "Should have Path as a non-mandatory System.String parameter" {
            $CommandUnderTest | Should -HaveParameter Path -Type System.String -Mandatory:$false
        }
        It "Should have FilePath as a non-mandatory System.String parameter" {
            $CommandUnderTest | Should -HaveParameter FilePath -Type System.String -Mandatory:$false
        }
        It "Should have Type as a non-mandatory System.String parameter" {
            $CommandUnderTest | Should -HaveParameter Type -Type System.String -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory System.Management.Automation.SwitchParameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter -Mandatory:$false
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
