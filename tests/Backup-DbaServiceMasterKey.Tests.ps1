param($ModuleName = 'dbatools')

Describe "Backup-DbaServiceMasterKey" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Backup-DbaServiceMasterKey
        }
        It "Should have SqlInstance as a non-mandatory parameter of type Dataplat.Dbatools.Parameter.DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a non-mandatory parameter of type System.Management.Automation.PSCredential" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have KeyCredential as a non-mandatory parameter of type System.Management.Automation.PSCredential" {
            $CommandUnderTest | Should -HaveParameter KeyCredential
        }
        It "Should have SecurePassword as a non-mandatory parameter of type System.Security.SecureString" {
            $CommandUnderTest | Should -HaveParameter SecurePassword
        }
        It "Should have Path as a non-mandatory parameter of type System.String" {
            $CommandUnderTest | Should -HaveParameter Path
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
        It "Should have WhatIf as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter WhatIf
        }
        It "Should have Confirm as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter Confirm
        }
    }

    Context "Can backup a service master key" {
        BeforeAll {
            $securePassword = ConvertTo-SecureString -String "GoodPass1234!" -AsPlainText -Force
            $results = Backup-DbaServiceMasterKey -SqlInstance $global:instance1 -Confirm:$false -SecurePassword $securePassword
        }

        AfterAll {
            Remove-Item -Path $results.Path -ErrorAction SilentlyContinue -Confirm:$false
        }

        It "backs up the SMK" {
            $results.Status | Should -Be "Success"
        }
    }
}
