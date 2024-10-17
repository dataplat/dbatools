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
        It "Should have OutputFile as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter OutputFile -Type String -Not -Mandatory
        }
        It "Should have Overwrite as a non-mandatory SwitchParameter" {
            $CommandUnderTest | Should -HaveParameter Overwrite -Type Switch -Not -Mandatory
        }
        It "Should have Event as a non-mandatory String[] parameter" {
            $CommandUnderTest | Should -HaveParameter Event -Type String[] -Not -Mandatory
        }
        It "Should have OutputColumn as a non-mandatory String[] parameter" {
            $CommandUnderTest | Should -HaveParameter OutputColumn -Type String[] -Not -Mandatory
        }
        It "Should have Filter as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter Filter -Type String -Not -Mandatory
        }
        It "Should have EnableException as a non-mandatory SwitchParameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Not -Mandatory
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
