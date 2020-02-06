$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'Name', 'Path', 'FilePath', 'InputObject', 'Architecture', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
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
        $results = Get-DbaKbUpdate -Name KB2992080 | Select -First 1 | Save-DbaKbUpdate -Path C:\temp
        $results.Name -match 'aspnet'
        $results | Remove-Item -Confirm:$false
    }
}