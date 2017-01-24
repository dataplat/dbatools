#Thank you Warren http://ramblingcookiemonster.github.io/Testing-DSC-with-Pester-and-AppVeyor/

if(-not $PSScriptRoot)
{
    $PSScriptRoot = Split-Path $MyInvocation.MyCommand.Path -Parent
}
$Verbose = @{}
if($env:APPVEYOR_REPO_BRANCH -and $env:APPVEYOR_REPO_BRANCH -notlike "master")
{
    $Verbose.add("Verbose",$True)
}



$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path).Replace('.Tests.', '.')
Import-Module $PSScriptRoot\..\internal\$sut -Force

Describe "Get-FilteredRestoreFile tests" {
    Context "Test Connections and Error handling" {
        It "Should throw on a bad SQL connection" {
            Mock Connect-SQLServer {throw}
            {Get-FilteredRestoreFile -files c:\dummy -sqlserver bad\bad} | Should Throw
        }
    }
    Context "Test filtering"{
        $date = get-date('01/01/2017')
        $BackupArray = (@{BackupType='';BackupTypeDescription='';BackupStartDate=$date;LastLSN='1'},@{BackupType='';BackupTypeDescription='';BackupStartDate=$date;LastLSN='1'})
        $files = (Get-ChildItem $MyInvocation.MyCommand.Path)
        mock Read-DbaBackUpHeader {$BackupArray}
        mock Connect-SQLServer {$true}
        It "should Throw with no initial full backup" {
            {Get-FilteredRestoreFile -files $files -sqlserver bad\bad} | Should Throw
        }
        $BackupArray = [PSCustomObject]@{BackupType='1';BackupTypeDescription='';BackupStartDate=$date;LastLSN='10'}
        #$BackupArray = @([PSCustomObject]@{BackupType='1';BackupTypeDescription='';BackupStartDate=$date;LastLSN='10'},[PSCustomObject]@{BackupType='1';BackupTypeDescription='';BackupStartDate=$date;LastLSN='10'})
        mock Read-DbaBackUpHeader {$BackupArray}
        $results =  Get-FilteredRestoreFile -files $files -sqlserver bad\bad


        It "Single File - Should return 1 file" {
            ($results | measure-object).count | Should be 1
        }
        It "Single File - Should be a full backup" {
            $results[0].BackupType | Should be 1
        }
        $BackupArray = @([PSCustomObject]@{BackupType='1';BackupTypeDescription='Full Backup';BackupStartDate=$date;LastLSN='10'},
                        [PSCustomObject]@{BackupType='2';BackupTypeDescription='Transaction Log';BackupStartDate=$date.AddMinutes(30);LastLSN='20'},
                        [PSCustomObject]@{BackupType='2';BackupTypeDescription='Transaction Log';BackupStartDate=$date.AddMinutes(60);LastLSN='30'})
        mock Read-DbaBackUpHeader {$BackupArray}
        New-item "TestDrive:\full.bak" -ItemType File
        $Files = get-item testdrive:\full.bak
        $results =  Get-FilteredRestoreFile -files $files -sqlserver bad\bad
        It "Should return 3 files" {
            ($results | measure-object).count | Should be 3
        }
        It "Should return 1 full backup" {
            ($results | where-object {$_.BackupType -eq 1} | measure-object).count | Should be 1
        }
        It "Should return 2 log backups" {
            ($results | where-object {$_.BackupTypeDescription -eq 'Transaction Log'} | measure-object).count | Should be 2
        }
        $BackupArray = @([PSCustomObject]@{BackupType='1';BackupTypeDescription='Full Backup';BackupStartDate=$date;LastLSN='10'},
        [PSCustomObject]@{BackupType='2';BackupTypeDescription='Transaction Log';BackupStartDate=$date.AddMinutes(30);LastLSN='20'},
        [PSCustomObject]@{BackupType='2';BackupTypeDescription='Transaction Log';BackupStartDate=$date.AddMinutes(35);LastLSN='21'},
        [PSCustomObject]@{BackupType='3';BackupTypeDescription='Database Differential';BackupStartDate=$date.AddMinutes(45);LastLSN='25'},
        [PSCustomObject]@{BackupType='2';BackupTypeDescription='Transaction Log';BackupStartDate=$date.AddMinutes(55);LastLSN='28'},
        [PSCustomObject]@{BackupType='2';BackupTypeDescription='Transaction Log';BackupStartDate=$date.AddMinutes(60);LastLSN='30'})
        mock Read-DbaBackUpHeader {$BackupArray}
        $results =  Get-FilteredRestoreFile -files $files -sqlserver bad\bad
        It "Should return 4 files" {
            ($results | measure-object).count | Should be 4
        }
        It "Should return 1 full backup" {
            ($results | where-object {$_.BackupType -eq 1} | measure-object).count | Should be 1
        }
        It "Should return 2 log backups" {
            ($results | where-object {$_.BackupTypeDescription -eq 'Transaction Log'} | measure-object).count | Should be 2
        }
        It "Should return 1 Diff backup" {
            ($results | where-object {$_.BackupTypeDescription -eq 'Database Differential'} | measure-object).count | Should be 1
        }
        $BackupArray = @([PSCustomObject]@{BackupType='1';BackupTypeDescription='Full Backup';BackupStartDate=$date;LastLSN='10'},
        [PSCustomObject]@{BackupType='2';BackupTypeDescription='Transaction Log';BackupStartDate=$date.AddMinutes(30);LastLSN='20'},
        [PSCustomObject]@{BackupType='2';BackupTypeDescription='Transaction Log';BackupStartDate=$date.AddMinutes(35);LastLSN='21'},
        [PSCustomObject]@{BackupType='3';BackupTypeDescription='Database Differential';BackupStartDate=$date.AddMinutes(45);LastLSN='25'},
        [PSCustomObject]@{BackupType='2';BackupTypeDescription='Transaction Log';BackupStartDate=$date.AddMinutes(50);LastLSN='28'},
        [PSCustomObject]@{BackupType='3';BackupTypeDescription='Database Differential';BackupStartDate=$date.AddMinutes(55);LastLSN='29'},
        [PSCustomObject]@{BackupType='2';BackupTypeDescription='Transaction Log';BackupStartDate=$date.AddMinutes(60);LastLSN='30'},
        [PSCustomObject]@{BackupType='2';BackupTypeDescription='Transaction Log';BackupStartDate=$date.AddMinutes(70);LastLSN='31'},
        [PSCustomObject]@{BackupType='2';BackupTypeDescription='Transaction Log';BackupStartDate=$date.AddMinutes(80);LastLSN='32'})
        mock Read-DbaBackUpHeader {$BackupArray}
        $results =  Get-FilteredRestoreFile -files $files -sqlserver bad\bad
        It "Should return 6 files" {
            ($results | measure-object).count | Should be 6
        }
        It "Should return 1 full backup" {
            ($results | where-object {$_.BackupType -eq 1} | measure-object).count | Should be 1
        }
        It "Should return 3 log backups" {
            ($results | where-object {$_.BackupTypeDescription -eq 'Transaction Log'} | measure-object).count | Should be 3
        }
        It "Should return 2 Diff backup" {
            ($results | where-object {$_.BackupTypeDescription -eq 'Database Differential'} | measure-object).count | Should be 2
        }
        $results =  Get-FilteredRestoreFile -files $files -sqlserver bad\bad -RestoreTime $date.addminutes(65)
                It "Time Filter - Should return 5 files" {
            ($results | measure-object).count | Should be 5
        }
        It "Time Filter - Should return 1 full backup" {
            ($results | where-object {$_.BackupType -eq 1} | measure-object).count | Should be 1
        }
        It "Time Filter - Should return 2 log backups" {
            ($results | where-object {$_.BackupTypeDescription -eq 'Transaction Log'} | measure-object).count | Should be 2
        }
        It "Time Filter - Should return 2 Diff backup" {
            ($results | where-object {$_.BackupTypeDescription -eq 'Database Differential'} | measure-object).count | Should be 2
        }
    }
    

}