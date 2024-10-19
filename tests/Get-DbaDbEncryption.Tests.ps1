param($ModuleName = 'dbatools')

Describe "Get-DbaDbEncryption" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbEncryption
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database
        }
        It "Should have ExcludeDatabase as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase
        }
        It "Should have IncludeSystemDBs as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter IncludeSystemDBs
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Integration Tests" -Tag "IntegrationTests" {
        BeforeAll {
            . "$PSScriptRoot\constants.ps1"
            $random = Get-Random
            $cert = "dbatoolsci_getcert$random"
            $password = ConvertTo-SecureString -String (Get-Random) -AsPlainText -Force
            New-DbaDbCertificate -SqlInstance $global:instance1 -Name $cert -Password $password
        }

        AfterAll {
            Get-DbaDbCertificate -SqlInstance $global:instance1 -Certificate $cert | Remove-DbaDbCertificate -Confirm:$false
        }

        It "Should find a certificate named $cert" {
            $results = Get-DbaDbEncryption -SqlInstance $global:instance1
            ($results.Name -match 'dbatoolsci').Count | Should -BeGreaterThan 0
        }
    }
}
