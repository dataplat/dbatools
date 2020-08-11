$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
    Context "Validate parameters" {
        [object[]]$params = (Get-Command $CommandName).Parameters.Keys | Where-Object {$_ -notin ('whatif', 'confirm')}
        [object[]]$knownParameters = 'SqlInstance', 'SqlCredential', 'Database', 'InputObject', 'EnableException'
        $knownParameters += [System.Management.Automation.PSCmdlet]::CommonParameters
        It "Should only contain our specific parameters" {
            (@(Compare-Object -ReferenceObject ($knownParameters | Where-Object {$_}) -DifferenceObject $params).Count ) | Should Be 0
        }
    }
}

Describe "$CommandName Integration Tests" -Tags "IntegrationTests" {
    Context "Should not munge system databases." {

        $dbs = @( "master", "model", "tempdb", "msdb" )

        It "Should not attempt to remove system databases." {
            foreach ($db in $dbs) {
                $db1 = Get-DbaDatabase -SqlInstance $script:instance1 -Database $db
                Remove-DbaDatabase -Confirm:$false -SqlInstance $script:instance1 -Database $db
                $db2 = Get-DbaDatabase -SqlInstance $script:instance1 -Database $db
                $db2.Name | Should Be $db1.Name
            }
        }

        It "Should not take system databases offline or change their status." {
            foreach ($db in $dbs) {
                $db1 = Get-DbaDatabase -SqlInstance $script:instance1 -Database $db
                Remove-DbaDatabase -Confirm:$false -SqlInstance $script:instance1 -Database $db
                $db2 = Get-DbaDatabase -SqlInstance $script:instance1 -Database $db
                $db2.Status | Should Be $db1.Status
                $db2.IsAccessible | Should Be $db1.IsAccessible
            }
        }
    }
    Context "Should remove user databases and return useful errors if it cannot." {
        It "Should remove a non system database." {
            Remove-DbaDatabase -Confirm:$false -SqlInstance $script:instance1 -Database singlerestore
            Get-DbaProcess -SqlInstance $script:instance1 -Database singlerestore | Stop-DbaProcess
            Restore-DbaDatabase -SqlInstance $script:instance1 -Path $script:appveyorlabrepo\singlerestore\singlerestore.bak -WithReplace
            (Get-DbaDatabase -SqlInstance $script:instance1 -Database singlerestore).IsAccessible | Should Be $true
            Remove-DbaDatabase -Confirm:$false -SqlInstance $script:instance1 -Database singlerestore
            Get-DbaDatabase -SqlInstance $script:instance1 -Database singlerestore | Should Be $null
        }
    }
    Context "Should remove restoring database and return useful errors if it cannot." {
        It "Should remove a non system database." {
            Remove-DbaDatabase -Confirm:$false -SqlInstance $script:instance1 -Database singlerestore
            Get-DbaProcess -SqlInstance $script:instance1 -Database singlerestore | Stop-DbaProcess
            Restore-DbaDatabase -SqlInstance $script:instance1 -Path $script:appveyorlabrepo\singlerestore\singlerestore.bak -WithReplace -NoRecovery
            (Connect-DbaInstance -SqlInstance $script:instance1).Databases['singlerestore'].IsAccessible | Should Be $false
            Remove-DbaDatabase -Confirm:$false -SqlInstance $script:instance1 -Database singlerestore
            Get-DbaDatabase -SqlInstance $script:instance1 -Database singlerestore | Should Be $null
        }
    }
}