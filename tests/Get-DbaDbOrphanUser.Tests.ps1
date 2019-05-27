$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'ExcludeDatabase', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}


Describe "$commandname Integration Tests" -Tag "IntegrationTests" {
    BeforeAll {
        $loginsq = @'
CREATE LOGIN [dbatoolsci_orphan1] WITH PASSWORD = N'password1', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;
CREATE LOGIN [dbatoolsci_orphan2] WITH PASSWORD = N'password2', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;
CREATE LOGIN [dbatoolsci_orphan3] WITH PASSWORD = N'password3', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;
CREATE DATABASE dbatoolsci_orphan;
'@
        $server = Connect-DbaInstance -SqlInstance $script:instance1
        $null = Remove-DbaLogin -SqlInstance $server -Login dbatoolsci_orphan1, dbatoolsci_orphan2, dbatoolsci_orphan3 -Force -Confirm:$false
        $null = Remove-DbaDatabase -SqlInstance $server -Database dbatoolsci_orphan -Confirm:$false
        $null = Invoke-DbaQuery -SqlInstance $server -Query $loginsq
        $usersq = @'
CREATE USER [dbatoolsci_orphan1] FROM LOGIN [dbatoolsci_orphan1];
CREATE USER [dbatoolsci_orphan2] FROM LOGIN [dbatoolsci_orphan2];
CREATE USER [dbatoolsci_orphan3] FROM LOGIN [dbatoolsci_orphan3];
'@
        Invoke-DbaQuery -SqlInstance $server -Query $usersq -Database dbatoolsci_orphan
        $dropOrphan = "DROP LOGIN [dbatoolsci_orphan1];DROP LOGIN [dbatoolsci_orphan2];"
        Invoke-DbaQuery -SqlInstance $server -Query $dropOrphan
    }
    AfterAll {
        $server = Connect-DbaInstance -SqlInstance $script:instance1
        $null = Remove-DbaLogin -SqlInstance $server -Login dbatoolsci_orphan1, dbatoolsci_orphan2, dbatoolsci_orphan3 -Force -Confirm:$false
        $null = Remove-DbaDatabase -SqlInstance $server -Database dbatoolsci_orphan -Confirm:$false
    }
    It "shows time taken for preparation" {
        1 | Should -Be 1
    }
    $results = Get-DbaDbOrphanUser -SqlInstance $script:instance1 -Database dbatoolsci_orphan
    It "Finds two orphans" {
        $results.Count | Should -Be 2
        foreach ($user in $Users) {
            $user.User | Should -BeIn @('dbatoolsci_orphan1', 'dbatoolsci_orphan2')
            $user.DatabaseName | Should -Be 'dbatoolsci_orphan'
        }
    }
    It "has the correct properties" {
        $result = $results[0]
        $ExpectedProps = 'ComputerName,InstanceName,SqlInstance,DatabaseName,User'.Split(',')
        ($result.PsObject.Properties.Name | Sort-Object) | Should Be ($ExpectedProps | Sort-Object)
    }
}