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
        New-Item "TestDrive:\TestFolder\full" -ItemType Directory
        Context "Function should exist with correct name" {
            It "Should exist" {
                $FunctionFile | Should Contain "function Get-OlaHRestoreFiles"
            }
        }
        Context "$Name Parameter tests" {
            It "Should accept a correct path" {
                {Get-OlaHRestoreFiles -path TestDrive:\TestFolder} | Should Not Throw           
            }
            It "Should error with an incorrect path" {
                {Get-OlaHRestoreFiles -path TestDrive:\TestFolder2} | Should Throw        
            }
        }
        Context "$Name checking for file finding" {
            New-Item "TestDrive:\TestFolder\full\full1.bak" -ItemType File
            New-Item "TestDrive:\TestFolder\full\full2.bak" -ItemType File
            New-Item "TestDrive:\TestFolder\full\full1.txt" -ItemType File
            $results = Get-OlaHRestoreFiles -Path TestDrive:\TestFolder
            It "Should return an array of System.IO.FileSystemInfo" {
                $results | Should BeOfType System.IO.FileSystemInfo
            }
            It "Should find 2 bak files in FULL"{
                $results.count | should be 2
            }
            It "Should not return the txt file"{
                ($results | Where-Object {$_.Extension -eq ".txt"}| Measure-Object).count  | Should Be 0
            }
            New-Item "TestDrive:\TestFolder\log\" -ItemType Directory
            New-Item "TestDrive:\TestFolder\log\log1.trn" -ItemType File
            New-Item "TestDrive:\TestFolder\log\log2.trn" -ItemType File
            New-Item "TestDrive:\TestFolder\log\log1.txt" -ItemType File
            $results = Get-OlaHRestoreFiles -Path TestDrive:\TestFolder
            It "Should find 4 files in total"{
                $results.count | should be 4
            }
            It "Should return 2 trn files" {
                ($results | Where-Object{$_.extension -eq ".trn"}).count | Should be 2
            }
            It "Should return 2 bak files" {
                ($results | Where-Object{$_.extension -eq ".bak"}).count | Should be 2
            }
            It "Should not return the txt files"{
                ($results | Where-Object {$_.Extension -eq ".txt"}| Measure-Object).count  | Should Be 0
            }
            New-Item "TestDrive:\TestFolder\diff\" -ItemType Directory
            New-Item "TestDrive:\TestFolder\diff\diff1.bak" -ItemType File
            New-Item "TestDrive:\TestFolder\diff\diff2.bak" -ItemType File
            New-Item "TestDrive:\TestFolder\diff\diff1.txt" -ItemType File
            $results = Get-OlaHRestoreFiles -Path TestDrive:\TestFolder
            It "Should find 4 files in total"{
                $results.count | should be 6
            }
            It "Should return 2 trn files" {
                ($results | Where-Object{$_.extension -eq ".trn"}).count | Should be 2
            }
            It "Should return 4 bak files" {
                ($results | Where-Object{$_.extension -eq ".bak"}).count | Should be 4
            }
            
            It "Should not return the txt files"{
                ($results | Where-Object {$_.Extension -eq ".txt"}| Measure-Object).count  | Should Be 0
            }
        }
}#describe 
    