param($ModuleName = 'dbatools')

Describe "New-DbaXESmartCsvWriter" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command New-DbaXESmartCsvWriter
        }
        It "has all the required parameters" {
            $requiredParameters = @(
                "OutputFile",
                "Overwrite",
                "Event",
                "OutputColumn",
                "Filter",
                "EnableException"
            )
            foreach ($param in $requiredParameters) {
                $CommandUnderTest | Should -HaveParameter $param
            }
        }
    }

    Context "Creates a smart object" {
        It "returns the object with all of the correct properties" {
            $results = New-DbaXESmartCsvWriter -Event abc -OutputColumn one, two -Filter What -OutputFile C:\temp\abc.csv
            $results.OutputFile | Should -Be 'C:\temp\abc.csv'
            $results.Overwrite | Should -Be $false
            $results.OutputColumns | Should -Contain 'one'
            $results.Filter | Should -Be 'What'
            $results.Events | Should -Contain 'abc'
        }
    }
}
