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
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "ComputerName",
                "Credential",
                "VersionNumber",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
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
