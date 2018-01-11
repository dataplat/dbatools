<#
	The below statement stays in for every test you build.
#>
$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1","")
Write-Host -Object "Running $PSCommandPath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"

<#
	Unit test is required for any command added
#>
Describe "$CommandName Unit Tests" -Tag 'UnitTests' {
	InModuleScope dbatools {
		#mock Connect-SqlInstance { $true }
        mock Test-DbaSqlPath { $true }

        Context "Validate parameters" {
			<#
			The $paramCount is adjusted based on the parameters your command will have.

			The $defaultParamCount is adjusted based on what type of command you are writing the test for:
				- Commands that *do not* include SupportShouldProcess, set defaultParamCount    = 11
				- Commands that *do* include SupportShouldProcess, set defaultParamCount        = 13
		#>
			$paramCount = 4
			$defaultParamCount = 11
			[object[]]$params = (Get-ChildItem function:\Get-DbaFilestream).Parameters.Keys
			$knownParameters = 'SqlInstance', 'SqlCredential', 'Credential', 'EnableException'
			It "Should contain our specific parameters" {
				( (Compare-Object -ReferenceObject $knownParameters -DifferenceObject $params -IncludeEqual | Where-Object SideIndicator -eq "==").Count ) | Should Be $paramCount
			}
			It "Should only contain $paramCount parameters" {
				$params.Count - $defaultParamCount | Should Be $paramCount
			}
        }

        Context "Test Connection" {
            Mock Connect-SqlInstance -MockWith { throw }
            It "Should throw on a bad connection" {
                { Get-DbaFileStream -SqlInstance (Get-Random) -EnableException $true } | Should Throw
            }
        }

		Context "Test Output" {
			Mock Connect-SqlInstance -MockWith {
				$obj = [PSCustomObject]@{
					NetName              = 'SQLServer'
					InstanceName         = 'MSSQLSERVER'
					DomainInstanceName   = 'SQLServer'
					ServiceName          = 'BASEServiceName'
					VersionMajor         = 9
					Configuration    = [PSCustomObject]@{
                        FileStreamAccessLevel = [PSCustomObject]@{
                            DisplayName = 'filestream access level'
                            Number      = '1580'
                            Minimum     = '0'
                            Maximum     = '2'
                            IsDynamic   = 'True'
                            IsAdvanced  = 'False'
                            Description = 'Sets the FILESTREAM access level'
                            RunValue    = '2'
                            ConfigValue = '2'
                        }
                    }
                }

				$obj.PSObject.TypeNames.Clear()
				$obj.PSObject.TypeNames.Add("Microsoft.SqlServer.Management.Smo.Server")
				return $obj
            }
            Mock Get-DbaSpConfigure -MockWith {
                $obj = [PSCustomObject]@{

                }
            }
            $results = Get-DbaFileStream -SqlInstance 'SQLServer'
            It "Instance level access should return 2" {
                $results.InstanceAccessLevel | should Be 2
            }
            It "Should return 'FileStream Enabled for T-Sql and Win-32 Access'" {
                $results.InstanceAccessLevelDesc | Should Be "Full access enabled"
            }
        }
	}
}