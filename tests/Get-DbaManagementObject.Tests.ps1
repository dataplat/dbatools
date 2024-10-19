param($ModuleName = 'dbatools')

Describe "Get-DbaManagementObject" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaManagementObject
        }
        It "Should have ComputerName as a parameter" {
            $CommandUnderTest | Should -HaveParameter ComputerName
        }
        It "Should have Credential as a parameter" {
            $CommandUnderTest | Should -HaveParameter Credential
        }
        It "Should have VersionNumber as a parameter" {
            $CommandUnderTest | Should -HaveParameter VersionNumber
        }
        It "Should have EnableException as a parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
        }
    }

    Context "Get-DbaManagementObject Integration Test" {
        BeforeAll {
            $results = Get-DbaManagementObject -ComputerName $env:COMPUTERNAME
        }

        It "returns results" {
            $results | Should -Not -BeNullOrEmpty
        }

        It "has the correct properties" {
            $result = $results[0]
            $ExpectedProps = 'ComputerName', 'Version', 'Loaded', 'LoadTemplate'
            $result.PSObject.Properties.Name | Should -Be $ExpectedProps
        }

        It "Returns the version specified" {
            $versionResults = Get-DbaManagementObject -ComputerName $env:COMPUTERNAME -VersionNumber 16
            $versionResults | Should -Not -BeNullOrEmpty
        }
    }
}
