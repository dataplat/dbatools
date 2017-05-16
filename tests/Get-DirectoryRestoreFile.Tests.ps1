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
Describe "Get-DirectoryRestoreFile Unit Tests" -Tag 'Unittests'{
    Context "Test Path handling" {
         Mock Test-Path {$false}
         Mock Write-Warning {
            throw}
        It "Should throw on an invalid Path"{
           { Get-DirectoryRestoreFile -Path c:\temp\} | Should Throw
        }
        It 'Calls Test-Path Mock Once' {
        $assertMockParams = @{
            'CommandName' = 'Test-Path'
            'Times' = 1
            'Exactly' = $true
        }
        Assert-MockCalled @assertMockParams 
    }
            It 'Calls Write-Warning Mock Once' {
        $assertMockParams = @{
            'CommandName' = 'Write-Warning'
            'Times' = 1
            'Exactly' = $true
        }
        Assert-MockCalled @assertMockParams 
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
            ($results | Where-Object {$_.Fullname -like '*\backups\Full.bak'}).count | Should be 1
        }
        It "Should return 2 trn files" {
            ($results | Where-Object {$_.Fullname -like '*\backups\*.trn'}).count | Should be 2
        }
        It "Should not contain log2b.trn" {
            ($results | Where-Object {$_.Fullname -like '*\backups\*log2b.trn'}).count | Should be 0            
        }
    }
}
