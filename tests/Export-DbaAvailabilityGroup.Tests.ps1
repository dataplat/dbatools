$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    Context "exports ags" {
        $results = Export-DbaAvailabilityGroup -SqlInstance $script:instance3
        It "returns file objects and one should be the name of the availability group" {
            $results.BaseName | Should -Contain 'dbatoolsci_agroup'
        }
        It "the files it returns should contain the term 'CREATE AVAILABILITY GROUP'" {
            $results | Select-String 'CREATE AVAILABILITY GROUP' | Should -Not -Be $null
        }
        $results | Remove-Item -ErrorAction SilentlyContinue
        $results = Export-DbaAvailabilityGroup -SqlInstance $script:instance3 -AvailabilityGroup dbatoolsci_agroup -FilePath C:\temp
        It "returns a single result" {
            $results.BaseName | Should -Be 'dbatoolsci_agroup'
        }
        It "the file it returns should contain the term 'CREATE AVAILABILITY GROUP'" {
            $results | Select-String 'CREATE AVAILABILITY GROUP' | Should -Not -Be $null
        }
        It "the file's path should match C:\temp" {
            $results.FullName -match 'C:\\temp' | Should -Be $true
        }
        $results | Remove-Item -ErrorAction SilentlyContinue
    }
}
# $script:instance2 - to make it appear in the proper place on appveyor