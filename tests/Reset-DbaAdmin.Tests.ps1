$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    AfterAll {
        Get-DbaProcess -SqlInstance $script:instance2 -Login dbatoolsci_resetadmin | Stop-DbaProcess -WarningAction SilentlyContinue
        (Get-DbaLogin -SqlInstance $script:instance2 -Login dbatoolsci_resetadmin).Drop()
    }
    Context "adds a sql login" {
        It "adds the login as sysadmin" {
            $password = ConvertTo-SecureString -Force -AsPlainText resetadmin1
            $cred = New-Object System.Management.Automation.PSCredential ("dbatoolsci_resetadmin", $password)
            Reset-DbaAdmin -SqlInstance $script:instance2 -Login dbatoolsci_resetadmin -SecurePassword $password -Confirm:$false -WarningAction SilentlyContinue
            $server = Connect-DbaInstance -SqlInstance $script:instance2 -Credential $cred
            $server.Name | Should Be $script:instance2
            $server.ConnectionContext.FixedServerRoles -match 'SysAdmin'
        }
    }
}