$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'Name', 'Path', 'FilePath', 'InputObject', 'Architecture', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    It "downloads a small update" {
        $results = Save-DbaKbUpdate -Name KB2992080 -Path C:\temp
        $results.Name -match 'aspnet'
        $results | Remove-Item -Confirm:$false
    }
    It "supports piping" {
        $results = Get-DbaKbUpdate -Name KB2992080 | select -First 1 | Save-DbaKbUpdate -Path C:\temp
        $results.Name -match 'aspnet'
        $results | Remove-Item -Confirm:$false
    }
    It "Download multiple updates" {
        $results = Save-DbaKbUpdate -Name KB2992080, KB4513696 -Path C:\temp
        $results.Count | Should -Be 2
        $results | Remove-Item -Confirm:$false

        $results = Get-DbaKbUpdate -Name KB2992080, KB4513696 | Save-DbaKbUpdate -Path C:\temp
        $results.Count | Should -Be 2
        $results | Remove-Item -Confirm:$false
    }

    # see https://github.com/sqlcollaborative/dbatools/issues/6745
    It "Ensuring that variable scope doesn't impact the command negatively" {
        $filter = "SQLServer*-KB-*x64*.exe"

        $results = Save-DbaKbUpdate -Name KB4513696 -Path C:\temp
        $results.Count | Should -Be 1
        $results | Remove-Item -Confirm:$false
    }
}