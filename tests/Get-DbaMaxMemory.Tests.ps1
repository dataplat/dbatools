## Thank you Warren http://ramblingcookiemonster.github.io/Testing-DSC-with-Pester-and-AppVeyor/

if(-not $PSScriptRoot) {
    $PSScriptRoot = Split-Path $MyInvocation.MyCommand.Path -Parent
}

$Verbose = @{}
if($env:APPVEYOR_REPO_BRANCH -and $env:APPVEYOR_REPO_BRANCH -notlike "master") {
    $Verbose.add("Verbose",$true)
}


$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path).Replace('.Tests.', '.')
Import-Module "$PSScriptRoot\..\functions\$sut" -Force
Import-Module PSScriptAnalyzer
## Added PSAvoidUsingPlainTextForPassword as credential is an object and therefore fails. We can ignore any rules here under special circumstances agreed by admins :-)
$rules = Get-ScriptAnalyzerRule | Where-Object {$_.RuleName -notin ('PSAvoidUsingPlainTextForPassword') }
$name = $sut.Split('.')[0]

Describe 'Script Analyzer Tests' {
    Context "Testing $name for Standard Processing" {
        foreach ($rule in $rules) { 
            $index = $rules.IndexOf($rule)
            It "passes the PSScriptAnalyzer Rule number $index - $rule  " {
                (Invoke-ScriptAnalyzer -Path "$PSScriptRoot\..\functions\$sut" -IncludeRule $rule.RuleName).Count | Should Be 0 
            }
        }
    }
}

## Load the command
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
if ([System.Version]::TryParse($leaf, [ref]$parsedVersion)) {
	$ModuleName = Split-Path $parent -Leaf
}
else {
	$ModuleName = $leaf
}

# Removes all versions of the module from the session before importing
Get-Module $ModuleName | Remove-Module

# Because ModuleBase includes version number, this imports the required version
# of the module
$null = Import-Module $ModuleBase\$ModuleName.psd1 -PassThru -ErrorAction Stop 


## Validate functionality. 

Describe $name {
    InModuleScope dbatools {
        Context 'Validate input arguments' {
            It 'SqlServer parameter is empty' {
                Mock Connect-SqlServer { throw System.Data.SqlClient.SqlException }
                { Get-DbaMaxMemory -SqlServer '' -WarningAction Stop 3> $null } | Should Throw
            }

            It 'SqlServer parameter host cannot be found' {
                Mock Connect-SqlServer { throw System.Data.SqlClient.SqlException }
                { Get-DbaMaxMemory -SqlServer 'ABC' -WarningAction Stop 3> $null } | Should Throw
            }
        }

        Context 'Validate functionality ' {
            It 'Server name reported correctly the installed memory' {
                Mock Connect-SqlServer { 
                    return @{
				        Name = 'ABC'
			        }
                } 
                
                (Get-DbaMaxMemory -SqlServer 'ABC').Server | Should be 'ABC'
            }  
        
            It 'Server under-report by 1MB the memory installed on the host' {
                Mock Connect-SqlServer { 
                    return @{
                        PhysicalMemory = 1023
			        }
                } 
                
                (Get-DbaMaxMemory -SqlServer 'ABC').TotalMB | Should be 1024
            }     
            
            It 'Server reports correctly the memory installed on the host' {
                Mock Connect-SqlServer { 
                    return @{
                        PhysicalMemory = 1024
			        }
                } 
                
                (Get-DbaMaxMemory -SqlServer 'ABC').TotalMB | Should be 1024
            }      

            It 'Memory allocated to SQL Server instance reported' {
                Mock Connect-SqlServer { 
                    return @{
                        Configuration = @{
                            MaxServerMemory = @{
                                ConfigValue = 2147483647
                            }
                        }
			        }
                } 
                
                (Get-DbaMaxMemory -SqlServer 'ABC').SqlMaxMB | Should be 2147483647
            }  
        }
    }
}
