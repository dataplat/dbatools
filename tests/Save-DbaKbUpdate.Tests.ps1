$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [array]$params = ([Management.Automation.CommandMetaData]$ExecutionContext.SessionState.InvokeCommand.GetCommand($CommandName, 'Function')).Parameters.Keys
        [object[]]$knownParameters = 'Name', 'Path', 'FilePath', 'InputObject', 'Architecture', 'EnableException'

        It "Should only contain our specific parameters" {
            Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params | Should -BeNullOrEmpty
        }
    }
}

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    It "downloads a small update" {
        $results = Save-DbaKbUpdate -Name KB2992080 -Architecture All -Path C:\temp
        $results.Name -match 'aspnet'
        $results | Remove-Item -Confirm:$false
    }
    It "supports piping" {
        $results = Get-DbaKbUpdate -Name KB2992080 | select -First 1 | Save-DbaKbUpdate -Architecture All -Path C:\temp
        $results.Name -match 'aspnet'
        $results | Remove-Item -Confirm:$false
    }
    It "Download multiple updates" {
        $results = Save-DbaKbUpdate -Name KB2992080, KB4513696 -Architecture All -Path C:\temp

        # basic retry logic in case the first download didn't get all of the files
        if ($null -eq $results -or $results.Count -ne 2) {
            Write-Message -Level Warning -Message "Retrying..."
            if ($results.Count -gt 0) {
                $results | Remove-Item -Confirm:$false
            }
            Start-Sleep -s 30
            $results = Save-DbaKbUpdate -Name KB2992080, KB4513696 -Architecture All -Path C:\temp
        }

        $results.Count | Should -Be 2
        $results | Remove-Item -Confirm:$false

        # download multiple updates via piping
        $results = Get-DbaKbUpdate -Name KB2992080, KB4513696 | Save-DbaKbUpdate -Architecture All -Path C:\temp

        # basic retry logic in case the first download didn't get all of the files
        if ($null -eq $results -or $results.Count -ne 2) {
            Write-Message -Level Warning -Message "Retrying..."
            if ($results.Count -gt 0) {
                $results | Remove-Item -Confirm:$false
            }
            Start-Sleep -s 30
            $results = Get-DbaKbUpdate -Name KB2992080, KB4513696 | Save-DbaKbUpdate -Architecture All -Path C:\temp
        }

        $results.Count | Should -Be 2
        $results | Remove-Item -Confirm:$false
    }

    # see https://github.com/sqlcollaborative/dbatools/issues/6745
    It "Ensuring that variable scope doesn't impact the command negatively" {
        $filter = "SQLServer*-KB-*x64*.exe"

        $results = Save-DbaKbUpdate -Name KB4513696 -Architecture All -Path C:\temp
        $results.Count | Should -Be 1
        $results | Remove-Item -Confirm:$false
    }
}