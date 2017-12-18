$CommandName = $MyInvocation.MyCommand.Name.Replace(".Tests.ps1","")
Write-Host -Object "Running $PSCommandpath" -ForegroundColor Cyan
. "$PSScriptRoot\constants.ps1"
. "$PSScriptRoot\..\internal\Connect-SqlInstance.ps1"

Describe "$commandname Unit Tests" -Tag 'UnitTests'{
	InModuleScope dbatools {
		#mock Connect-SqlInstance { $true }
        mock Test-DbaSqlPath { $true }
        
        Context "Test Connection" {
            Mock Connect-SqlInstance -MockWith { throw }
            It "Should throw on a bad connection" {
                { Get-DbaFileStream -SqlInstance test -EnableException $true } | Should Throw
            }
        }
		
		Context "Test Output" {
			Mock Connect-SqlInstance -MockWith {
				$obj = [PSCustomObject]@{
					Name                 = 'BASEName'
					NetName              = 'BASENetName'
					InstanceName         = 'BASEInstanceName'
					DomainInstanceName   = 'BASEDomainInstanceName'
					InstallDataDirectory = 'BASEInstallDataDirectory'
					ErrorLogPath         = 'BASEErrorLog_{0}_{1}_{2}_Path' -f "'", '"', ']'
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
            $results = Get-DbaFileStream -SqlInstance istance\tests -verbose
            It "Should return 2" {
                $results.FileStreamStateId | should Be 2
            }
            It "Should return 'FileStream Enabled for T-Sql and Win-32 Access'" {
                $results.FileStreamState | Should be "FileStream Enabled for T-Sql and Win-32 Access"
            }
        }
    }
}