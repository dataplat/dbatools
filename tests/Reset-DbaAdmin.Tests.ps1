$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Login', 'SecurePassword', 'Force', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tag "IntegrationTests" {
    AfterAll {
        Get-DbaProcess -SqlInstance $script:instance2 -Login dbatoolsci_resetadmin | Stop-DbaProcess -WarningAction SilentlyContinue
        Get-DbaLogin -SqlInstance $script:instance2 -Login dbatoolsci_resetadmin| Remove-DbaLogin -Confirm:$false
    }
    Context "adds a sql login" {
        It "adds the login as sysadmin" {
            $password = ConvertTo-SecureString -Force -AsPlainText resetadmin1
            $cred = New-Object System.Management.Automation.PSCredential ("dbatoolsci_resetadmin", $password)
            $results = Reset-DbaAdmin -SqlInstance $script:instance2 -Login dbatoolsci_resetadmin -SecurePassword $password -Confirm:$false
            $results.Name | Should -Be dbatoolsci_resetadmin
            $results.IsMember("sysadmin") | Should -Be $true
        }
    }
}