param($ModuleName = 'dbatools')

Describe "New-DbaComputerCertificateSigningRequest" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaComputerCertificateSigningRequest
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "ComputerName",
                "Credential",
                "ClusterInstanceName",
                "Path",
                "FriendlyName",
                "KeyLength",
                "Dns",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
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
