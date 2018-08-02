$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    Context "returns the proper transport" {
        $results = Get-DbaConnection -SqlInstance $script:instance1
        foreach ($result in $results) {
            It "returns an scheme" {
                $result.AuthScheme -eq 'ntlm' -or $result.AuthScheme -eq 'Kerberos' | Should -Be $true
            }
        }
    }
}