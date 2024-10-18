param($ModuleName = 'dbatools')

Describe "Get-DbaDbEncryption" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbEncryption
        }
        It "Should have SqlInstance as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[]
        }
        It "Should have SqlCredential as a parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type System.Management.Automation.PSCredential
        }
        It "Should have Database as a parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type System.Object[]
        }
        It "Should have ExcludeDatabase as a parameter" {
            $CommandUnderTest | Should -HaveParameter ExcludeDatabase -Type System.Object[]
        }
        It "Should have IncludeSystemDBs as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter IncludeSystemDBs -Type System.Management.Automation.SwitchParameter
        }
        It "Should have EnableException as a switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter
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
