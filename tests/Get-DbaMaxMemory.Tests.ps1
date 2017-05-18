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
                (Invoke-ScriptAnalyzer -Path "$PSScriptRoot\..\functions\$sut" -IncludeRule $rule.RuleName).Count | Should Be 0
            }
        }
    }
}


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
