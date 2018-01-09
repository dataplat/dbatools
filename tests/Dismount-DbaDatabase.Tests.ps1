$commandname = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1", "")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"


Describe "$commandname Integration Tests" -Tags "IntegrationTests" {

    # Setting up the environment we need to test the cmdlet
    BeforeAll {
        # Everything in here gets executed before anything else in this context

        # Setting up variables names. If you want them to persist between all of the pester blocks, they can be moved outside
        $dbname = "dbatoolsci_detachattach"
        # making room in the remote case a db with the same name exists
        $null = Get-DbaDatabase -SqlInstance $script:instance2 -Database $dbname | Remove-DbaDatabase -Confirm:$false
        # restoring from the "common test data" (see https://github.com/sqlcollaborative/appveyor-lab)
        $null = Restore-DbaDatabase -SqlInstance $script:instance2 -Path C:\github\appveyor-lab\detachattach\detachattach.bak -DatabaseName $dbname -WithReplace

        # memorizing $fileStructure for a later test
        $fileStructure = New-Object System.Collections.Specialized.StringCollection

        foreach ($file in (Get-DbaDatabaseFile -SqlInstance $script:instance2 -Database $dbname).PhysicalName) {
            $null = $fileStructure.Add($file)
        }
    }

    # Everything we create/touch/mess with should be reverted to a "clean" state whenever possible
    AfterAll {
        # this gets executed always (think "finally" in try/catch/finally) and it's the best place for final cleanups
        $null = Attach-DbaDatabase -SqlInstance $script:instance2 -Database $dbname -FileStructure $script:fileStructure
        $null = Get-DbaDatabase -SqlInstance $script:instance2 -Database $dbname | Remove-DbaDatabase -Confirm:$false
    }

    # Actual tests
    Context "Detaches a single database and tests to ensure the alias still exists" {
        $results = Detach-DbaDatabase -SqlInstance $script:instance2 -Database $dbname -Force

        It "was successfull" {
            $results.DetachResult | Should Be "Success"
        }

        It "removed just one database" {
            $results.Database | Should Be $dbname
        }

        It "has the correct properties" {
            $ExpectedProps = 'ComputerName,InstanceName,SqlInstance,Database,DetachResult'.Split(',')
            ($results.PsObject.Properties.Name | Sort-Object) | Should Be ($ExpectedProps | Sort-Object)
        }
    }
    Context "Database Detachment" {
        BeforeAll {
            $server = Connect-DbaInstance -SqlInstance $script:instance2
            $db1 = "dbatoolsci_dbsetstate_detached"
            $db2 = "dbatoolsci_dbsetstate_detached_withSnap"
            $server.Query("CREATE DATABASE $db1")
            $server.Query("CREATE DATABASE $db2")
            $null = New-DbaDatabaseSnapshot -SqlInstance $script:instance2 -Database $db2
            $fileStructure = New-Object System.Collections.Specialized.StringCollection
            foreach ($file in (Get-DbaDatabaseFile -SqlInstance $script:instance2 -Database $db1).PhysicalName) {
                $null = $fileStructure.Add($file)
            }
            Stop-DbaProcess -SqlInstance $script:instance2 -Database $db1
        }
        AfterAll {
            $null = Remove-DbaDatabaseSnapshot -SqlInstance $script:instance2 -Database $db2 -Force
            $null = Attach-DbaDatabase -SqlInstance $script:instance2 -Database $db1 -FileStructure $fileStructure
            $null = Get-DbaDatabase -SqlInstance $script:instance2 -Database $db1, $db2 | Remove-DbaDatabase -Confirm:$false
        }

        It "Skips detachment if database is snapshotted" {
            $result = Dismount-DbaDatabase -SqlInstance $script:instance2 -Database $db2 -Force -WarningAction SilentlyContinue -WarningVariable warn
            $result | Should Be $null
            $warn -match "snapshot" | Should Be $true
            $result = Get-DbaDatabase -SqlInstance $script:instance2 -Database $db2
            $result | Should Not Be $null
        }
        $null = Stop-DbaProcess -SqlInstance $script:instance2 -Database $db1
        $result = Dismount-DbaDatabase -SqlInstance $script:instance2 -Database $db1
        It "Detaches the database correctly" {
            $result = Get-DbaDatabase -SqlInstance $script:instance2 -Database $db1
            $result | Should Be $null
        }
    }
}