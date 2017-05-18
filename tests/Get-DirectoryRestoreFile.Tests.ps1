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

# Test functionality

Describe "Get-DirectoryRestoreFile Unit Tests" -Tag 'Unittests'{
    Context "Test Path handling" {
        It "Should throw on an invalid Path"{
            Mock Test-Path { $false }
            { Get-DirectoryRestoreFile -Path c:\temp\ } | Should Throw
        }
    }
    Context "Returning Files from one folder" {
        New-item "TestDrive:\backups\" -ItemType directory
        New-item "TestDrive:\backups\full.bak" -ItemType File
        New-item "TestDrive:\backups\log1.trn" -ItemType File
        New-item "TestDrive:\backups\log2.trn" -ItemType File
        New-item "TestDrive:\backups\b\" -ItemType directory
        New-item "TestDrive:\backups\b\log2b.trn" -ItemType File
        $results = Get-DirectoryRestoreFile -Path TestDrive:\backups
        It "Should Return an array of FileInfo" {
            $results | Should BeOfType System.IO.FileSystemInfo
        }
        It "Should Return 3 files" {
            $results.count | Should Be 3
        }
        It "Should return 1 bak file" {
            ($results | Where-Object { $_.Fullname -like '*\backups\Full.bak' }).count | Should be 1
        }
        It "Should return 2 trn files" {
            ($results | Where-Object { $_.Fullname -like '*\backups\*.trn' }).count | Should be 2
        }
        It "Should not contain log2b.trn" {
            ($results | Where-Object { $_.Fullname -like '*\backups\*log2b.trn' }).count | Should be 0
        }
    }
}
