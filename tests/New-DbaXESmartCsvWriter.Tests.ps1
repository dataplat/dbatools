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
        It "Should have OutputFile as a non-mandatory System.String parameter" {
            $CommandUnderTest | Should -HaveParameter OutputFile
        }
        It "Should have Overwrite as a non-mandatory System.Management.Automation.SwitchParameter" {
            $CommandUnderTest | Should -HaveParameter Overwrite
        }
        It "Should have Event as a non-mandatory System.String[] parameter" {
            $CommandUnderTest | Should -HaveParameter Event
        }
        It "Should have OutputColumn as a non-mandatory System.String[] parameter" {
            $CommandUnderTest | Should -HaveParameter OutputColumn
        }
        It "Should have Filter as a non-mandatory System.String parameter" {
            $CommandUnderTest | Should -HaveParameter Filter
        }
        It "Should have EnableException as a non-mandatory System.Management.Automation.SwitchParameter" {
            $CommandUnderTest | Should -HaveParameter EnableException
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
