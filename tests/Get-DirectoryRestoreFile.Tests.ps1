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
if (Test-Path "$PSScriptRoot\..\functions\$sut")
{
    ."$PSScriptRoot\..\functions\$sut"
    $FunctionFile = "$PSScriptRoot\..\functions\$sut"
}else {
    ."$PSScriptRoot\..\internal\$sut"
    $FunctionFile = "$PSScriptRoot\..\internal\$sut"
}

$ModuleBase = Split-Path -Parent $MyInvocation.MyCommand.Path

# For tests in .\Tests subdirectory
if ((Split-Path $ModuleBase -Leaf) -eq 'Tests')
{
	$ModuleBase = Split-Path $ModuleBase -Parent
}

# Handles modules in version directories
$leaf = Split-Path $ModuleBase -Leaf
$parent = Split-Path $ModuleBase -Parent
$parsedVersion = $null
if ([System.Version]::TryParse($leaf, [ref]$parsedVersion))
{
	$ModuleName = Split-Path $parent -Leaf
}
else
{
	$ModuleName = $leaf
}

$Name = ((Split-Path $FunctionFile -Leaf).split('.'))[0]
# Removes all versions of the module from the session before importing
Get-Module $ModuleName | Remove-Module

# Because ModuleBase includes version number, this imports the required version
# of the module
$null = Import-Module $ModuleBase\$ModuleName.psd1 -PassThru -ErrorAction Stop 
. "$Modulebase\functions\DynamicParams.ps1"
Get-ChildItem "$Modulebase\internal\" |% {. $_.fullname}

    Describe "$Name Tests" {
        New-Item "TestDrive:\TestFolder" -ItemType Directory
        Context "Function should exist with correct name" {
            It "Should exist" {
                $FunctionFile | Should Contain "function Get-DirectoryRestoreFile"
            }
        }
        Context "$Name Parameter tests" {
            It "Should accept a correct path" {
                {Get-DirectoryRestoreFile -path TestDrive:\TestFolder} | Should Not Throw           
            }
            It "Should error with an incorrect path" {
                {Get-DirectoryRestoreFile -path TestDrive:\TestFolder2} | Should Throw        
            }
        }
        New-Item "TestDrive:\TestFolder\FullBackup.Bak" -ItemType File
        New-Item "TestDrive:\TestFolder\LogBackup.trn" -ItemType File
        New-Item "TestDrive:\TestFolder\NotABackup.txt" -ItemType File
        Context "$Name is picky about path endings" {
            It "Should take a bare path" {
                $bareresults = Get-DirectoryRestoreFile -Path TestDrive:\TestFolder
                $bareresults.count | Should be 2
            }
            It "Should take a \ ended path" {
                $bareresults = Get-DirectoryRestoreFile -Path TestDrive:\TestFolder\
                $bareresults.count | Should be 2
            }
            It "Should take a * ended path" {
                $bareresults = Get-DirectoryRestoreFile -Path TestDrive:\TestFolder*
                $bareresults.count | Should be 2
            }
            It "Should take a \* ended path" {
                $bareresults = Get-DirectoryRestoreFile -Path TestDrive:\TestFolder\*
                $bareresults.count | Should be 2
            }
        }
        Context "$Name scan tests" {
            $results = Get-DirectoryRestoreFile -Path TestDrive:\TestFolder\
            It "Should return an array of System.IO.FileSystemInfo" {
                $results | Should BeOfType System.IO.FileSystemInfo
            }
            It "Check TestDrive" {
                (Get-ChildItem TestDrive:\TestFolder\).count | should be 3
            }
            It "Should return 2 files" {
                $results.count | Should Be 2
            }
            It "Should not return the txt file"{
                ($results | Where-Object {$_.Extension -eq ".txt"}| Measure-Object).count  | Should Be 0
            }
        }
}#describe
    
    