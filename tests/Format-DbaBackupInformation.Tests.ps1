$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1","")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

Describe "$commandname Integration Tests" -Tags "UnitTests" {
	
	Context "Rename a Database" {
        $History = Get-DbaBackupInformation -Import -Path $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\ContinuePointTest.xml
        $output = $history | Format-DbaBackupInformation -ReplaceDatabaseName 'Pester'
        It "Should have a database name of Pester" {
            ($output | Where-Object {$_.Database -ne 'Pester'}).count | Should be 0
        }
    
    }

    Context "Test it works as a parameter as well"{
        $History = Get-DbaBackupInformation -Import -Path $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\ContinuePointTest.xml
        $output = Format-DbaBackupInformation -BackupHistory $History -ReplaceDatabaseName 'Pester'
        It "Should have a database name of Pester" {
            ($output | Where-Object {$_.Database -ne 'Pester'}).count | Should be 0
        }       
    }

    Context "Rename 2 dbs using a hash" {
        $History = Get-DbaBackupInformation -Import -Path $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\ContinuePointTest.xml
        $History += Get-DbaBackupInformation -Import -Path $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\RestoreTimeClean.xml
        $output = Format-DbaBackupInformation -BackupHistory $History -ReplaceDatabaseName @{'ContinuePointTest'='Spiggy';'RestoreTimeClean'='Eldritch'}
        It "Should have no databases other than spiggy and eldritch"{
            ($output | Where-Object {$_.Database -notin ('Spiggy','Eldritch')}).count | Should be 0    
        } 
        It "Should have renamed all RestoreTimeCleans to Eldritch"{
            ($Output | Where-Object {$_.OriginalDatabase -eq 'RestoreTimeClean'} | Where-Object {$_.Database -ne 'Eldritch'}).count | Should be 0
        }
        It "Should have renamed all ContinuePointTest to Spiggy"{
            ($Output | Where-Object {$_.OriginalDatabase -eq 'ContinuePointTest'} | Where-Object {$_.Database -ne 'Spiggy'}).count | Should be 0
        }

    }

    Context "Rename 1 dbs using a hash" {
        $History = Get-DbaBackupInformation -Import -Path $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\ContinuePointTest.xml
        $History += Get-DbaBackupInformation -Import -Path $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\RestoreTimeClean.xml
        $output = Format-DbaBackupInformation -BackupHistory $History -ReplaceDatabaseName @{'ContinuePointTest'='Alice'}
        It "Should have no databases other than spiggy and eldritch"{
            ($output | Where-Object {$_.Database -notin ('RestoreTimeClean','Alice')}).count | Should be 0    
        } 
        It "Should have left RestoreTimeClean alone"{
            ($Output | Where-Object {$_.OriginalDatabase -eq 'RestoreTimeClean'} | Where-Object {$_.Database -ne 'RestoreTimeClean'}).count | Should be 0
        }
        It "Should have renamed all ContinuePointTest to Alice"{
            ($Output | Where-Object {$_.OriginalDatabase -eq 'ContinuePointTest'} | Where-Object {$_.Database -ne 'Alice'}).count | Should be 0
        }

    }
}