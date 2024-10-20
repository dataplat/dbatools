param($ModuleName = 'dbatools')

Describe "New-DbaComputerCertificateSigningRequest" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaComputerCertificateSigningRequest
        }

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
        It "has the required parameter: <_>" -ForEach $requiredParameters {
            $CommandUnderTest | Should -HaveParameter $PSItem
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
