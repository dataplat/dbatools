$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $login = "dbatoolsci_removelogin"
        $password = 'MyV3ry$ecur3P@ssw0rd'
        $securePassword = ConvertTo-SecureString $password -AsPlainText -Force
        $newlogin = New-DbaLogin -SqlInstance $script:instance1 -Login $login -Password $securePassword
    }

    It "removes the login" {
        $results = Remove-DbaLogin -SqlInstance $script:instance1 -Login $login -Confirm:$false
        $results.Status -eq "Dropped"
        $login1 = Get-Dbalogin -SqlInstance $script:instance1 -login $removed
        $null -eq $login1
    }
}
