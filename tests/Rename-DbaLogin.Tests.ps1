$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "IntegrationTests" {
    BeforeAll {
        $login = "dbatoolsci_renamelogin"
        $renamed = "dbatoolsci_renamelogin2"
        $password = 'MyV3ry$ecur3P@ssw0rd'
        $securePassword = ConvertTo-SecureString $password -AsPlainText -Force
        $newlogin = New-DbaLogin -SqlInstance $script:instance1 -Login $login -Password $securePassword
    }
    AfterAll {
        Stop-DbaProcess -SqlInstance $script:instance1 -Login $renamed
        (Get-Dbalogin -SqlInstance $script:instance1 -Login $renamed).Drop()
    }

    It "renames the login" {
        $results = Rename-DbaLogin -SqlInstance $script:instance1 -Login $login -NewLogin $renamed
        $results.Status -eq "Successful"
        $results.OldLogin = $login
        $results.NewLogin = $renamed
        $login1 = Get-Dbalogin -SqlInstance $script:instance1 -login $renamed
        $null -ne $login1
    }
}
