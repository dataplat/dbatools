param($ModuleName = 'dbatools')

Describe "Get-DbaKbUpdate" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaKbUpdate
        }
        It "Should have Name as a non-mandatory String[] parameter" {
            $CommandUnderTest | Should -HaveParameter Name -Type String[] -Not -Mandatory
        }
        It "Should have Simple as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter Simple -Type Switch -Not -Mandatory
        }
        It "Should have Language as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter Language -Type String -Not -Mandatory
        }
        It "Should have EnableException as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Not -Mandatory
        }
    }

    Context "Integration Tests" {
        It "successfully connects and parses link and title" {
            $results = Get-DbaKbUpdate -Name KB4057119
            $results.Link | Should -Match 'download.windowsupdate.com'
            $results.Title | Should -Match 'Cumulative Update'
            $results.KBLevel | Should -Be 4057119
        }

        It "test with the -Simple param" {
            $results = Get-DbaKbUpdate -Name KB4577194 -Simple
            $results.Link | Should -Match 'download.windowsupdate.com'
            $results.Title | Should -Match 'Cumulative Update'
            $results.KBLevel | Should -Be 4577194
        }

        It "Calling script uses a variable named filter" {
            $filter = "SQLServer*-KB-*x64*.exe"

            $results = Get-DbaKbUpdate -Name KB4564903
            $results.KBLevel | Should -Be 4564903
            $results.Link | Should -Match 'download.windowsupdate.com'
            $results.Title | Should -Match 'Cumulative Update'
        }

        It "Call with multiple KBs" {
            $results = Get-DbaKbUpdate -Name KB4057119, KB4577194, KB4564903

            # basic retry logic in case the first download didn't get all of the files
            if ($null -eq $results -or $results.Count -ne 3) {
                Write-Warning "Retrying..."
                Start-Sleep -Seconds 30
                $results = Get-DbaKbUpdate -Name KB4057119, KB4577194, KB4564903
            }

            $results.KBLevel | Should -Contain 4057119
            $results.KBLevel | Should -Contain 4577194
            $results.KBLevel | Should -Contain 4564903
        }

        It "Call without specific language" {
            $results = Get-DbaKbUpdate -Name KB5003279
            $results.KBLevel | Should -Be 5003279
            $results.Classification | Should -Match 'Service Packs'
            $results.Link | Should -Match '-enu_'
        }

        It "Call with specific language" {
            $results = Get-DbaKbUpdate -Name KB5003279 -Language ja
            $results.KBLevel | Should -Be 5003279
            $results.Classification | Should -Match 'Service Packs'
            $results.Link | Should -Match '-jpn_'
        }
    }
}
