param($ModuleName = 'dbatools')

Describe "Remove-DbaDatabase" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaDatabase
        }

        $params = @(
            "SqlInstance",
            "SqlCredential",
            "Database",
            "InputObject",
            "EnableException"
        )
        It "has the required parameter: <_>" -ForEach $params {
            $CommandUnderTest | Should -HaveParameter $PSItem
        }
    }

    Context "Should not munge system databases" {
        BeforeAll {
            $dbs = @( "master", "model", "tempdb", "msdb" )
        }

        It "Should not attempt to remove system databases" {
            foreach ($db in $dbs) {
                $db1 = Get-DbaDatabase -SqlInstance $global:instance1 -Database $db
                { Remove-DbaDatabase -Confirm:$false -SqlInstance $global:instance1 -Database $db } | Should -Not -Throw
                $db2 = Get-DbaDatabase -SqlInstance $global:instance1 -Database $db
                $db2.Name | Should -Be $db1.Name
            }
        }

        It "Should not take system databases offline or change their status" {
            foreach ($db in $dbs) {
                $db1 = Get-DbaDatabase -SqlInstance $global:instance1 -Database $db
                { Remove-DbaDatabase -Confirm:$false -SqlInstance $global:instance1 -Database $db } | Should -Not -Throw
                $db2 = Get-DbaDatabase -SqlInstance $global:instance1 -Database $db
                $db2.Status | Should -Be $db1.Status
                $db2.IsAccessible | Should -Be $db1.IsAccessible
            }
        }
    }

    Context "Should remove user databases and return useful errors if it cannot" {
        BeforeAll {
            Remove-DbaDatabase -Confirm:$false -SqlInstance $global:instance1 -Database singlerestore
            Get-DbaProcess -SqlInstance $global:instance1 -Database singlerestore | Stop-DbaProcess
            Restore-DbaDatabase -SqlInstance $global:instance1 -Path $env:appveyorlabrepo\singlerestore\singlerestore.bak -WithReplace
        }

        It "Should remove a non system database" {
            (Get-DbaDatabase -SqlInstance $global:instance1 -Database singlerestore).IsAccessible | Should -Be $true
            Remove-DbaDatabase -Confirm:$false -SqlInstance $global:instance1 -Database singlerestore
            Get-DbaDatabase -SqlInstance $global:instance1 -Database singlerestore | Should -BeNullOrEmpty
        }
    }

    Context "Should remove restoring database and return useful errors if it cannot" {
        BeforeAll {
            Remove-DbaDatabase -Confirm:$false -SqlInstance $global:instance1 -Database singlerestore
            Get-DbaProcess -SqlInstance $global:instance1 -Database singlerestore | Stop-DbaProcess
            Restore-DbaDatabase -SqlInstance $global:instance1 -Path $env:appveyorlabrepo\singlerestore\singlerestore.bak -WithReplace -NoRecovery
        }

        It "Should remove a non system database" {
            (Connect-DbaInstance -SqlInstance $global:instance1).Databases['singlerestore'].IsAccessible | Should -Be $false
            Remove-DbaDatabase -Confirm:$false -SqlInstance $global:instance1 -Database singlerestore
            Get-DbaDatabase -SqlInstance $global:instance1 -Database singlerestore | Should -BeNullOrEmpty
        }
    }
}
