param($ModuleName = 'dbatools')

Describe "Export-DbaPfDataCollectorSetTemplate" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Export-DbaPfDataCollectorSetTemplate
        }
        
        It "has all the required parameters" {
            $requiredParameters = @(
                "ComputerName",
                "Credential",
                "CollectorSet",
                "Path",
                "FilePath",
                "InputObject",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Command usage" -Tag "IntegrationTests" {
        BeforeAll {
            $null = Get-DbaPfDataCollectorSetTemplate -Template 'Long Running Queries' | Import-DbaPfDataCollectorSetTemplate
        }
        AfterAll {
            $null = Get-DbaPfDataCollectorSet -CollectorSet 'Long Running Queries' | Remove-DbaPfDataCollectorSet -Confirm:$false
        }

        It "returns a file system object when using pipeline input" {
            $results = Get-DbaPfDataCollectorSet -CollectorSet 'Long Running Queries' | Export-DbaPfDataCollectorSetTemplate
            $results.BaseName | Should -Be 'Long Running Queries'
        }

        It "returns a file system object when using parameter input" {
            $results = Export-DbaPfDataCollectorSetTemplate -CollectorSet 'Long Running Queries'
            $results.BaseName | Should -Be 'Long Running Queries'
        }
    }
}
