param($ModuleName = 'dbatools')

Describe "Get-DbaPfDataCollectorSetTemplate" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaPfDataCollectorSetTemplate
        }
        It "Should have Path as a non-mandatory String[] parameter" {
            $CommandUnderTest | Should -HaveParameter Path -Type String[] -Not -Mandatory
        }
        It "Should have Pattern as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter Pattern -Type String -Not -Mandatory
        }
        It "Should have Template as a non-mandatory String[] parameter" {
            $CommandUnderTest | Should -HaveParameter Template -Type String[] -Not -Mandatory
        }
        It "Should have EnableException as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Not -Mandatory
        }
    }

    Context "Verifying command returns all the required results" {
        It "returns not null values for required fields" {
            $results = Get-DbaPfDataCollectorSetTemplate
            foreach ($result in $results) {
                $result.Name | Should -Not -BeNullOrEmpty
                $result.Source | Should -Not -BeNullOrEmpty
                $result.Description | Should -Not -BeNullOrEmpty
            }
        }

        It "returns only one (and the proper) template" {
            $results = Get-DbaPfDataCollectorSetTemplate -Template 'Long Running Queries'
            $results.Name | Should -Be 'Long Running Queries'
        }
    }
}
