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
        new-Item "TestDrive:\TestFolder\full1.bak" -ItemType File
        new-Item "TestDrive:\TestFolder\log1a.trn" -ItemType File
        new-Item "TestDrive:\TestFolder\log2a.trn" -ItemType File
        new-Item "TestDrive:\TestFolder\full2.bak" -ItemType File
        new-Item "TestDrive:\TestFolder\log1b.trn" -ItemType File
        
        $Folder = Get-ChildItem TestDrive:\TestFolder\*
        
        Context "Function should exist with correct name" {
            It "Should exist" {
                $FunctionFile | Should Contain "function $name"
            }
        }
        Context "$(($Folder.gettype())[0].gettype()) - Testing Inputs and Outputs" {
            It "Should take an array of System.IO.FileSystemInfo" {
                {Filter-RestoreFiles -Files $Folder} | Should Not Throw
            }
             
            It "Should Return an array of System.IO.FileSystemInfo" {
                $result = Filter-RestoreFiles -Files $Folder
                $result | Should BeOfType System.IO.FileSystemInfo    
            }
        }
}#describe
    
    