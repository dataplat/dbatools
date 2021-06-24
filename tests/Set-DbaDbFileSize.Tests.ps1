$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object { $_ -notin ('whatif', 'confirm') }
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'GrowthType', 'Growth', 'InputObject', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object { $_ }) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $newdb = New-DbaDatabase -SqlInstance $script:instance2 -Name newdb
    }
    AfterAll {
        $newdb | Remove-DbaDatabase -Confirm:$false
    }
    Context "Should return file information for only newdb" {
        $results = Set-DbaDbFileSize -SqlInstance $script:instance2 -Database newdb
        foreach ($result in $results) {
            It "returns the proper info" {
                $result.Database | Should -Be "newdb"
                $result.GrowthType | Should -Be "MB"
                $result.Growth | Should -Be "64"
            }
        }
    }

    Context "Supports piping" {
        $results = Get-DbaDatabase $script:instance2 -Database newdb | Set-DbaDbFileSize
        foreach ($result in $results) {
            It "returns only newdb files" {
                $result.Database | Should -Be "newdb"
            }
        }
    }
}