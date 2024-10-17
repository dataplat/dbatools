param($ModuleName = 'dbatools')

Describe "Remove-DbaDatabase" {
    BeforeAll {
        . "$PSScriptRoot\constants.ps1"
    }

    Context "Validate parameters" {
        BeforeAll {
            $CommandUnderTest = Get-Command Remove-DbaDatabase
        }
        It "Should have SqlInstance parameter" {
            $CommandUnderTest | Should -HaveParameter SqlInstance -Type DbaInstanceParameter[] -Mandatory:$false
        }
        It "Should have SqlCredential parameter" {
            $CommandUnderTest | Should -HaveParameter SqlCredential -Type PSCredential -Mandatory:$false
        }
        It "Should have Database parameter" {
            $CommandUnderTest | Should -HaveParameter Database -Type Object[] -Mandatory:$false
        }
        It "Should have InputObject parameter" {
            $CommandUnderTest | Should -HaveParameter InputObject -Type Database[] -Mandatory:$false
        }
        It "Should have EnableException parameter" {
            $CommandUnderTest | Should -HaveParameter EnableException -Type Switch -Mandatory:$false
        }
    }

    Context "Should not munge system databases" {
        BeforeAll {
            $dbs = @( "master", "model", "tempdb", "msdb" )
        }

        It "Should not attempt to remove system databases" {
            foreach ($db in $dbs) {
                $db1 = Get-DbaDatabase -SqlInstance $global:instance1 -Database $db
                Remove-DbaDatabase -Confirm:$false -SqlInstance $global:instance1 -Database $db
                $db2 = Get-DbaDatabase -SqlInstance $global:instance1 -Database $db
                $db2.Name | Should -Be $db1.Name
            }
        }

        It "Should not take system databases offline or change their status" {
            foreach ($db in $dbs) {
                $db1 = Get-DbaDatabase -SqlInstance $global:instance1 -Database $db
                Remove-DbaDatabase -Confirm:$false -SqlInstance $global:instance1 -Database $db
                $db2 = Get-DbaDatabase -SqlInstance $global:instance1 -Database $db
                $db2.Status | Should -Be $db1.Status
                $db2.IsAccessible | Should -Be $db1.IsAccessible
            }
        }
    }

    Context "Should remove user databases and return useful errors if it cannot" {
        It "Should remove a non system database" {
            BeforeAll {
                Remove-DbaDatabase -Confirm:$false -SqlInstance $global:instance1 -Database singlerestore
                Get-DbaProcess -SqlInstance $global:instance1 -Database singlerestore | Stop-DbaProcess
                Restore-DbaDatabase -SqlInstance $global:instance1 -Path $env:appveyorlabrepo\singlerestore\singlerestore.bak -WithReplace
            }

            (Get-DbaDatabase -SqlInstance $global:instance1 -Database singlerestore).IsAccessible | Should -Be $true
            Remove-DbaDatabase -Confirm:$false -SqlInstance $global:instance1 -Database singlerestore
            Get-DbaDatabase -SqlInstance $global:instance1 -Database singlerestore | Should -BeNullOrEmpty
        }
    }

    Context "Should remove restoring database and return useful errors if it cannot" {
        It "Should remove a non system database" {
            BeforeAll {
                Remove-DbaDatabase -Confirm:$false -SqlInstance $global:instance1 -Database singlerestore
                Get-DbaProcess -SqlInstance $global:instance1 -Database singlerestore | Stop-DbaProcess
                Restore-DbaDatabase -SqlInstance $global:instance1 -Path $env:appveyorlabrepo\singlerestore\singlerestore.bak -WithReplace -NoRecovery
            }

            (Connect-DbaInstance -SqlInstance $global:instance1).Databases['singlerestore'].IsAccessible | Should -Be $false
            Remove-DbaDatabase -Confirm:$false -SqlInstance $global:instance1 -Database singlerestore
            Get-DbaDatabase -SqlInstance $global:instance1 -Database singlerestore | Should -BeNullOrEmpty
        }
    }
}
