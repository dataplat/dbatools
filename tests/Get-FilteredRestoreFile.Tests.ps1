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
. $PSScriptRoot\..\functions\Read-DbaBackupHeader.ps1

Describe "Get-FilteredRestoreFile Unit Tests" -Tag 'Unittests'{
    Context "Empty TLog Backup Issues" {
        $Header = ConvertFrom-Json -InputObject (Get-Content .\EmptyTlogData.json -raw)
        Mock Read-DbaBackupHeader {$Header}
        $Output = Get-FilteredRestoreFile -SqlServer 'TestSQL' -Files "c:\dummy.txt" -verbose
        $Output
        It "Should return an array of 3 items" {
            $Output[0].values.count | Should be 3
        }
        It "Should return 1 full backups" {
            ($Output[0].values | Where-Object {$_.BackupTypeDescription -eq 'Database'} | Measure-Object).count | Should Be 1
        }
        It "Should return 2 log backups" {
            ($Output[0].values | Where-Object {$_.BackupTypeDescription -eq 'Transaction Log'}).count | Should Be 2
        }
    }
}

