param($ModuleName = 'dbatools')

Describe "New-DbaComputerCertificateSigningRequest" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaComputerCertificateSigningRequest
        }
        It "Should have ComputerName as a non-mandatory parameter of type Dataplat.Dbatools.Parameter.DbaInstanceParameter[]" {
            $CommandUnderTest | Should -HaveParameter ComputerName -Type Dataplat.Dbatools.Parameter.DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have Credential as a non-mandatory parameter of type System.Management.Automation.PSCredential" {
            $CommandUnderTest | Should -HaveParameter Credential -Type System.Management.Automation.PSCredential -Mandatory:$false
        }
        It "Should have ClusterInstanceName as a non-mandatory parameter of type System.String" {
            $CommandUnderTest | Should -HaveParameter ClusterInstanceName -Type System.String -Mandatory:$false
        }
        It "Should have Path as a non-mandatory parameter of type System.String" {
            $CommandUnderTest | Should -HaveParameter Path -Type System.String -Mandatory:$false
        }
        It "Should have FriendlyName as a non-mandatory parameter of type System.String" {
            $CommandUnderTest | Should -HaveParameter FriendlyName -Type System.String -Mandatory:$false
        }
        It "Should have KeyLength as a non-mandatory parameter of type System.Int32" {
            $CommandUnderTest | Should -HaveParameter KeyLength -Type System.Int32 -Mandatory:$false
        }
        It "Should have Dns as a non-mandatory parameter of type System.String[]" {
            $CommandUnderTest | Should -HaveParameter Dns -Type System.String[] -Mandatory:$false
        }
        It "Should have EnableException as a non-mandatory switch parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type System.Management.Automation.SwitchParameter -Mandatory:$false
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
