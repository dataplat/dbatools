$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'InputObject', 'ConvertTo', 'Path', 'Suffix', 'NoPlanExport', 'NoQueryExport', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    AfterAll {
        Get-ChildItem "C:\temp\dbatoolsci" -Recurse | Remove-Item -ErrorAction Ignore
        Get-Item "C:\temp\dbatoolsci" | Remove-Item -ErrorAction Ignore
    }
    Context "Verifying output" {
        It "exports results to one file and creates directory if required" {
            $null = Invoke-DbaDiagnosticQuery -SqlInstance $script:instance2 -QueryName 'Memory Clerk Usage' | Export-DbaDiagnosticQuery -Path "C:\temp\dbatoolsci"
            (Get-ChildItem "C:\temp\dbatoolsci").Count | Should Be 1
        }
    }
}