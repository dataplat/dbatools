param($ModuleName = 'dbatools')

Describe "Save-DbaKbUpdate" {
    BeforeAll {
        $CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Save-DbaKbUpdate
        }
        It "Should have Name as a non-mandatory String[] parameter" {
            $CommandUnderTest | Should -HaveParameter Name -Type String[] -Not -Mandatory
        }
        It "Should have Path as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter Path -Type String -Not -Mandatory
        }
        It "Should have FilePath as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter FilePath -Type String -Not -Mandatory
        }
        It "Should have Architecture as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter Architecture -Type String -Not -Mandatory
        }
        It "Should have Language as a non-mandatory String parameter" {
            $CommandUnderTest | Should -HaveParameter Language -Type String -Not -Mandatory
        }
        It "Should have InputObject as a non-mandatory Object[] parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Object[] -Not -Mandatory
        }
        It "Should have EnableException as a non-mandatory Switch" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Not -Mandatory
        }
    }

    Context "Command usage" {
        It "downloads a small update" {
            $results = Save-DbaKbUpdate -Name KB2992080 -Architecture All -Path C:\temp
            $results.Name | Should -Match 'aspnet'
            $results | Remove-Item -Confirm:$false
        }

        It "supports piping" {
            $results = Get-DbaKbUpdate -Name KB2992080 | Select-Object -First 1 | Save-DbaKbUpdate -Architecture All -Path C:\temp
            $results.Name | Should -Match 'aspnet'
            $results | Remove-Item -Confirm:$false
        }

        It "Download multiple updates" {
            $results = Save-DbaKbUpdate -Name KB2992080, KB4513696 -Architecture All -Path C:\temp

            # basic retry logic in case the first download didn't get all of the files
            if ($null -eq $results -or $results.Count -ne 2) {
                Write-Warning "Retrying..."
                if ($results.Count -gt 0) {
                    $results | Remove-Item -Confirm:$false
                }
                Start-Sleep -Seconds 30
                $results = Save-DbaKbUpdate -Name KB2992080, KB4513696 -Architecture All -Path C:\temp
            }

            $results.Count | Should -Be 2
            $results | Remove-Item -Confirm:$false

            # download multiple updates via piping
            $results = Get-DbaKbUpdate -Name KB2992080, KB4513696 | Save-DbaKbUpdate -Architecture All -Path C:\temp

            # basic retry logic in case the first download didn't get all of the files
            if ($null -eq $results -or $results.Count -ne 2) {
                Write-Warning "Retrying..."
                if ($results.Count -gt 0) {
                    $results | Remove-Item -Confirm:$false
                }
                Start-Sleep -Seconds 30
                $results = Get-DbaKbUpdate -Name KB2992080, KB4513696 | Save-DbaKbUpdate -Architecture All -Path C:\temp
            }

            $results.Count | Should -Be 2
            $results | Remove-Item -Confirm:$false
        }

        # see https://github.com/dataplat/dbatools/issues/6745
        It "Ensuring that variable scope doesn't impact the command negatively" {
            $filter = "SQLServer*-KB-*x64*.exe"

            $results = Save-DbaKbUpdate -Name KB4513696 -Architecture All -Path C:\temp
            $results.Count | Should -Be 1
            $results | Remove-Item -Confirm:$false
        }
    }
}
