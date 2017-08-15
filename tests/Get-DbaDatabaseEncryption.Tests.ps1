$commandname = $MyInvocation.MyCommand.Name.Replace(".ps1","")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    Context "Test Retriving Certificate" {
        BeforeAll {
			$random = Get-Random
            $cert = "dbatoolsci_getcert$random"
            $password = ConvertTo-SecureString -String Get-Random -AsPlainText -Force
            New-DbaDatabaseCertificate -SqlInstance $script:instance1 -Name $cert -password $password
		}
		AfterAll {
            Get-DbaDatabaseCertificate -SqlInstance $script:instance1 -Certificate $cert | Remove-DbaDatabaseCertificate -confirm:$false
		}
        $results = Get-DbaDatabaseEncryption -SqlInstance $script:instance1 
        It "Should find a certificate named $cert" {
            ($results.Name -match 'dbatoolsci').Count -gt 0 | Should Be $true
        }
    }
}