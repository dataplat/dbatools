FUNCTION Find-DbaDatabase
{
	[CmdletBinding()]
	Param (
		[parameter(Position = 0, Mandatory = $true)]
		[Alias("ServerInstance", "SqlInstance", "SqlServers")]
		[string[]]$SqlServer,
		[System.Management.Automation.PSCredential]$SqlCredential,
        [string]$Database
	)
	BEGIN 
        {

        }
    PROCESS
        {
            
            FOREACH ($server in $SqlServer)
                {
                    TRY
			            {
				            Write-Verbose "Connecting to $server"
                            $server = Connect-SqlServer -SqlServer $SqlServer -SqlCredential $sqlcredential
			            }
		            CATCH
			            {
				            Write-Warning "Failed to connect to: $server"
                            break
			            }
                    #conn to db list
                }
        }
    END
        {

        }
}