param($ModuleName = 'dbatools')

Describe "Get-DbaDbOrphanUser" {
    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Get-DbaDbOrphanUser
        }

        It "has the required parameter: <_>" -ForEach @(
            "SqlInstance",
            "SqlCredential",
            "Database",
            "ExcludeDatabase",
            "EnableException"
        ) {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Command usage" {
        BeforeAll {
            . "$PSScriptRoot\constants.ps1"

            $loginsq = @'
CREATE LOGIN [dbatoolsci_orphan1] WITH PASSWORD = N'password1', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;
CREATE LOGIN [dbatoolsci_orphan2] WITH PASSWORD = N'password2', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;
CREATE LOGIN [dbatoolsci_orphan3] WITH PASSWORD = N'password3', CHECK_EXPIRATION = OFF, CHECK_POLICY = OFF;
CREATE DATABASE dbatoolsci_orphan;
'@
            $server = Connect-DbaInstance -SqlInstance $global:instance1
            $null = Remove-DbaLogin -SqlInstance $server -Login dbatoolsci_orphan1, dbatoolsci_orphan2, dbatoolsci_orphan3 -Force
            $null = Remove-DbaDatabase -SqlInstance $server -Database dbatoolsci_orphan
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
            $server = Connect-DbaInstance -SqlInstance $global:instance1
            $null = Remove-DbaLogin -SqlInstance $server -Login dbatoolsci_orphan1, dbatoolsci_orphan2, dbatoolsci_orphan3 -Force
            $null = Remove-DbaDatabase -SqlInstance $server -Database dbatoolsci_orphan
        }

        It "Finds two orphans" {
            $results = Get-DbaDbOrphanUser -SqlInstance $global:instance1 -Database dbatoolsci_orphan
            $results.Count | Should -Be 2
            foreach ($user in $results) {
                $user.User | Should -BeIn @('dbatoolsci_orphan1', 'dbatoolsci_orphan2')
                $user.DatabaseName | Should -Be 'dbatoolsci_orphan'
            }
        }

        It "Has the correct properties" {
            $results = Get-DbaDbOrphanUser -SqlInstance $global:instance1 -Database dbatoolsci_orphan
            $result = $results[0]
            $ExpectedProps = 'ComputerName', 'InstanceName', 'SqlInstance', 'DatabaseName', 'User', 'SmoUser'
            ($result.PsObject.Properties.Name | Sort-Object) | Should -Be ($ExpectedProps | Sort-Object)
        }
    }
}
