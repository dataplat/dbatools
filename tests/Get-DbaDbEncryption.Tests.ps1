param($ModuleName = 'dbatools')

Describe "Get-DbaDbEncryption" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbEncryption
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "Database",
                "ExcludeDatabase"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
            $CommandUnderTest | Should -HaveParameter IncludeSystemDBs
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
