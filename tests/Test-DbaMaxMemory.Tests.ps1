## Thank you Warren http://ramblingcookiemonster.github.io/Testing-DSC-with-Pester-and-AppVeyor/

if(-not $PSScriptRoot) {
	$PSScriptRoot = Split-Path $MyInvocation.MyCommand.Path -Parent
}

$Verbose = @{}
if($env:APPVEYOR_REPO_BRANCH -and $env:APPVEYOR_REPO_BRANCH -notlike "master") {
	$Verbose.add("Verbose", $true)
}


$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path).Replace('.Tests.', '.')
Import-Module "$PSScriptRoot\..\functions\$sut" -Force
Import-Module PSScriptAnalyzer
## Added PSAvoidUsingPlainTextForPassword as credential is an object and therefore fails. We can ignore any rules here under special circumstances agreed by admins :-)
$rules = Get-ScriptAnalyzerRule | Where-Object{$_.RuleName -notin ('PSAvoidUsingPlainTextForPassword') }
$name = $sut.Split('.')[0]

Describe 'Script Analyzer Tests' {
	Context "Testing $name for Standard Processing" {
		foreach ($rule in $rules) { 
			$index = $rules.IndexOf($rule)
			It "passes the PSScriptAnalyzer Rule number $index - $rule	" {
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
            It 'No "SQL Server" Windows service is running on the host' {
                Mock Get-Service { throw ParameterArgumentValidationError }
                { Test-DbaMaxMemory -SqlServer '' -WarningAction Stop 3> $null } | Should Throw
            }

			It 'SqlServer parameter is empty' {
				Mock Get-DbaMaxMemory -MockWith { return $null } 			
				Test-DbaMaxMemory -SqlServer '' 3> $null | Should be $null
			}

			It 'SqlServer parameter host cannot be found' {
				Mock Get-DbaMaxMemory -MockWith { return $null } 			
				Test-DbaMaxMemory -SqlServer 'ABC' 3> $null | Should be $null
			}

		}

		Context 'Validate functionality - Single Instance' {            
            Mock Resolve-SqlIpAddress -MockWith { return '10.0.0.1' } 
            Mock Get-Service -MockWith { 
                # Mocking Get-Service using PSCustomObject does not work. It needs to be mocked as object instead.               
                $service = New-Object System.ServiceProcess.ServiceController
                $service.DisplayName = 'SQL Server (ABC)'
                Add-Member -InputObject $service -MemberType NoteProperty -Name Status -Value 'Running'  -Force
                return $service
            } 

            It 'Connect to SQL Server' {
                Mock Get-DbaMaxMemory -MockWith { }

                $result = Test-DbaMaxMemory -SqlServer 'ABC'                

                Assert-MockCalled Resolve-SqlIpAddress -Scope It -Times 1                 
                Assert-MockCalled Get-Service -Scope It -Times 1 
                Assert-MockCalled Get-DbaMaxMemory -Scope It -Times 1 
            }
            
			It 'Connect to SQL Server and retrieve the "Max Server Memory" setting' {
                Mock Get-DbaMaxMemory -MockWith { 
                    return @{ SqlMaxMB = 2147483647 } 
                }

                (Test-DbaMaxMemory -SqlServer 'ABC').SqlMaxMB | Should be 2147483647               
			}
		
            It 'Calculate recommended memory - Single instance, Total 4GB, Expected 2GB, Reserved 2GB (.5x Memory)' {
                Mock Get-DbaMaxMemory -MockWith { 
                    return @{ TotalMB = 4096 } 
                }                

                $result = Test-DbaMaxMemory -SqlServer 'ABC'
                $result.InstanceCount | Should Be 1
                $result.RecommendedMB | Should Be 2048
            }

            It 'Calculate recommended memory - Single instance, Total 6GB, Expected 3GB, Reserved 3GB (Iterations => 2x 8GB)' {
                Mock Get-DbaMaxMemory -MockWith { 
                    return @{ TotalMB = 6144 } 
                }                

                $result = Test-DbaMaxMemory -SqlServer 'ABC'
                $result.InstanceCount | Should Be 1
                $result.RecommendedMB | Should Be 3072
            }

            It 'Calculate recommended memory - Single instance, Total 8GB, Expected 5GB, Reserved 3GB (Iterations => 2x 8GB)' {
                Mock Get-DbaMaxMemory -MockWith { 
                    return @{ TotalMB = 8192 } 
                }                

                $result = Test-DbaMaxMemory -SqlServer 'ABC'
                $result.InstanceCount | Should Be 1
                $result.RecommendedMB | Should Be 5120
            }

            It 'Calculate recommended memory - Single instance, Total 16GB, Expected 11GB, Reserved 5GB (Iterations => 4x 8GB)' {
                Mock Get-DbaMaxMemory -MockWith { 
                    return @{ TotalMB = 16384 } 
                }                

                $result = Test-DbaMaxMemory -SqlServer 'ABC'
                $result.InstanceCount | Should Be 1
                $result.RecommendedMB | Should Be 11264
            }

            It 'Calculate recommended memory - Single instance, Total 18GB, Expected 13GB, Reserved 5GB (Iterations => 1x 16GB, 3x 8GB)' {
                Mock Get-DbaMaxMemory -MockWith { 
                    return @{ TotalMB = 18432 } 
                }                

                $result = Test-DbaMaxMemory -SqlServer 'ABC'
                $result.InstanceCount | Should Be 1
                $result.RecommendedMB | Should Be 13312
            }

            It 'Calculate recommended memory - Single instance, Total 32GB, Expected 25GB, Reserved 7GB (Iterations => 2x 16GB, 4x 8GB)' {
                Mock Get-DbaMaxMemory -MockWith { 
                    return @{ TotalMB = 32768 } 
                }                

                $result = Test-DbaMaxMemory -SqlServer 'ABC'
                $result.InstanceCount | Should Be 1
                $result.RecommendedMB | Should Be 25600
            }
		}
	}
}
