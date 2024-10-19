param($ModuleName = 'dbatools')

Describe "Test-DbaInstanceName" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Test-DbaInstanceName
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "SqlInstance",
                "SqlCredential",
                "ExcludeSsrs",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Command tests servername" {
        BeforeAll {
            $results = Test-DbaInstanceName -SqlInstance $global:instance2
        }

        It "should say rename is not required" {
            $results.RenameRequired | Should -Be $false
        }

        It "returns the correct properties" {
            $ExpectedProps = 'ComputerName', 'InstanceName', 'SqlInstance', 'ServerName', 'NewServerName', 'RenameRequired', 'Updatable', 'Warnings', 'Blockers'
            $results.PSObject.Properties.Name | Should -Be $ExpectedProps
        }
    }
}
