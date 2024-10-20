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
        $requiredParameters = @(
            "Name",
            "Path",
            "FilePath",
            "Architecture",
            "Language",
            "InputObject",
            "EnableException"
        )
        It "has all the required parameters: <_>" -ForEach $requiredParameters {
            $CommandUnderTest | Should -HaveParameter $PSItem
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
