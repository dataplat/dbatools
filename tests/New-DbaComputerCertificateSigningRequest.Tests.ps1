param($ModuleName = 'dbatools')

Describe "New-DbaComputerCertificateSigningRequest" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaComputerCertificateSigningRequest
        }
        It "Should have ComputerName as a non-mandatory parameter of type DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter ComputerName -Type DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have Credential as a non-mandatory parameter of type PSCredential" {
            $CommandUnderTest | Should -HaveParameter Credential -Type PSCredential -Mandatory:$false
        }
        It "Should have ClusterInstanceName as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter ClusterInstanceName -Type String -Mandatory:$false
        }
        It "Should have Path as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter Path -Type String -Mandatory:$false
        }
        It "Should have FriendlyName as a non-mandatory parameter of type String" {
            $CommandUnderTest | Should -HaveParameter FriendlyName -Type String -Mandatory:$false
        }
        It "Should have KeyLength as a non-mandatory parameter of type Int32" {
            $CommandUnderTest | Should -HaveParameter KeyLength -Type Int32 -Mandatory:$false
        }
        It "Should have Dns as a non-mandatory parameter of type String[]" {
            $CommandUnderTest | Should -HaveParameter Dns -Type String[] -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Mandatory:$false
        }
    }

    Context "Command usage" {
        It "generates a new certificate" {
            $files = New-DbaComputerCertificateSigningRequest
            $files.Count | Should -Be 2
            $files | Remove-Item -Confirm:$false
        }
    }
}
