#Thank you Warren http://ramblingcookiemonster.github.io/Testing-DSC-with-Pester-and-AppVeyor/

if (-not $PSScriptRoot) {
    $PSScriptRoot = Split-Path $MyInvocation.MyCommand.Path -Parent
}
$Verbose = @{ }
if ($env:APPVEYOR_REPO_BRANCH -and $env:APPVEYOR_REPO_BRANCH -notlike "master") {
    $Verbose.add("Verbose", $True)
}

$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path).Replace('.Tests.', '.')
$Name = $sut.Split('.')[0]

Describe 'Script Analyzer Tests' -Tag @('ScriptAnalyzer') {
    Context "Testing $Name for Standard Processing" {
        foreach ($rule in $ScriptAnalyzerRules) {
            $i = $ScriptAnalyzerRules.IndexOf($rule)
            It "passes the PSScriptAnalyzer Rule number $i - $rule  " {
                (Invoke-ScriptAnalyzer -Path "$PSScriptRoot\..\internal\$sut" -IncludeRule $rule.RuleName).Count | Should Be 0
            }
        }
    }
}


# Test Functionality
. $PSScriptRoot\..\internal\Get-FilteredRestoreFile.ps1
. $PSScriptRoot\..\functions\Read-DbaBackupHeader.ps1
Describe "Get-FilteredRestoreFile Unit Tests" -Tag 'Unittests'{
    Context "Empty TLog Backup Issues" {
        $Header = ConvertFrom-Json -InputObject (Get-Content $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\EmptyTlogData.json -raw)
        Mock Read-DbaBackupHeader { $Header }
        $Output = Get-FilteredRestoreFile -SqlServer 'TestSQL' -Files "c:\dummy.txt"
        
        It "Should return an array of 3 items" {
            $Output[0].values.count | Should be 3
        }
        It "Should return 1 Full backups" {
            ($Output[0].values | Where-Object { $_.BackupTypeDescription -eq 'Database' } | Measure-Object).count | Should Be 1
        }
        It "Should return 0 Diff backups" {
            ($Output[0].values | Where-Object { $_.BackupTypeDescription -eq 'Database Differential' } | Measure-Object).count | Should Be 0
        }
        It "Should return 2 log backups" {
            ($Output[0].values | Where-Object { $_.BackupTypeDescription -eq 'Transaction Log' } | Measure-Object).count | Should Be 2
        }
    }
    Context "General Diff Restore" {
        $Header = ConvertFrom-Json -InputObject (Get-Content $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\DiffRestore.json -raw)
        Mock Read-DbaBackupHeader { $Header }
        $Output = Get-FilteredRestoreFile -SqlServer 'TestSQL' -Files "c:\dummy.txt"
        
        It "Should return an array of 7 items" {
            $Output[0].values.count | Should be 7
        }
        It "Should return 1 Full backups" {
            ($Output[0].values | Where-Object { $_.BackupTypeDescription -eq 'Database' } | Measure-Object).count | Should Be 1
        }
        It "Should return 1 Diff backups" {
            ($Output[0].values | Where-Object { $_.BackupTypeDescription -eq 'Database Differential' } | Measure-Object).count | Should Be 1
        }
        It "Should return 5 log backups" {
            ($Output[0].values | Where-Object { $_.BackupTypeDescription -eq 'Transaction Log' } | Measure-Object).count | Should Be 5
        }
    }
    Context "Missing Diff Restore" {
        $Header = ConvertFrom-Json -InputObject (Get-Content $PSScriptRoot\..\tests\ObjectDefinitions\BackupRestore\RawInput\DiffRestore.json -raw)
        $header = $header | Where-Object { $_.BackupTypeDescription -ne 'Database Differential' }
        Mock Read-DbaBackupHeader { $Header }
        $Output = Get-FilteredRestoreFile -SqlServer 'TestSQL' -Files "c:\dummy.txt"
        $Output
        It "Should return an array of 9 items" {
            $Output[0].values.count | Should be 9
        }
        It "Should return 1 Full backups" {
            ($Output[0].values | Where-Object { $_.BackupTypeDescription -eq 'Database' } | Measure-Object).count | Should Be 1
        }
        It "Should return 0 Diff backups" {
            ($Output[0].values | Where-Object { $_.BackupTypeDescription -eq 'Database Differential' } | Measure-Object).count | Should Be 0
        }
        It "Should return 8 log backups" {
            ($Output[0].values | Where-Object { $_.BackupTypeDescription -eq 'Transaction Log' } | Measure-Object).count | Should Be 8
        }
    }
}