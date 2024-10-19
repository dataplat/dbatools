param($ModuleName = 'dbatools')

Describe "Add-DbaComputerCertificate" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Add-DbaComputerCertificate
        }
        It "Should have ComputerName as a parameter" {
            $CommandUnderTest | Should -HaveParameter ComputerName
        }
        It "Should have Credential as a parameter" {
            $CommandUnderTest | Should -HaveParameter Credential
        }
        It "Should have SecurePassword as a parameter" {
            $CommandUnderTest | Should -HaveParameter SecurePassword
        }
        It "Should have Certificate as a parameter" {
            $CommandUnderTest | Should -HaveParameter Certificate
        }
        It "Should have Path as a parameter" {
            $CommandUnderTest | Should -HaveParameter Path
        }
        It "Should have Store as a parameter" {
            $CommandUnderTest | Should -HaveParameter Store
        }
        It "Should have Folder as a parameter" {
            $CommandUnderTest | Should -HaveParameter Folder
        }
        It "Should have Flag as a parameter" {
            $CommandUnderTest | Should -HaveParameter Flag
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Certificate is added properly" {
        BeforeAll {
            $results = Add-DbaComputerCertificate -Path $global:appveyorlabrepo\certificates\localhost.crt -Confirm:$false
        }

        It "Should show the proper thumbprint has been added" {
            $results.Thumbprint | Should -Be "29C469578D6C6211076A09CEE5C5797EEA0C2713"
        }

        It "Should be in LocalMachine\My Cert Store" {
            $results.PSParentPath | Should -Be "Microsoft.PowerShell.Security\Certificate::LocalMachine\My"
        }

        AfterAll {
            Remove-DbaComputerCertificate -Thumbprint 29C469578D6C6211076A09CEE5C5797EEA0C2713 -Confirm:$false
        }
    }
}
