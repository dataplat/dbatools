FUNCTION Get-DbaSchemaChangeHistory {
    <#
	.SYNOPSIS
	Gets DDL changes logged in the system trace.

	.DESCRIPTION
    Queries the default system trace for any DDL changes in the specified timeframe
    Only works with SQL 2005 and later, as the system trace didn't exist before then

	.PARAMETER SqlInstance
	SQL Server name or SMO object representing the SQL Server to connect to. This can be a collection and recieve pipeline input to allow the function
	to be executed against multiple SQL Server instances.

	.PARAMETER SqlCredential
	SqlCredential object to connect as. If not specified, current Windows login will be used.

	.PARAMETER Silent 
	Use this switch to disable any kind of verbose messages
	
	.NOTES
	Original Author: FirstName LastName (@twitterhandle and/or website)
	Tags: Migration, Backup
	
	Website: https://dbatools.io
	Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
	License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

	.LINK
	https://dbatools.io/Get-DbaJobCategory

	.EXAMPLE
	Get-DbaJobCategory -SqlInstance localhost
	Returns all SQL Agent Job Categories on the local default SQL Server instance

	.EXAMPLE
	Get-DbaJobCategory -SqlInstance localhost, sql2016
	Returns all SQL Agent Job Categories for the local and sql2016 SQL Server instances

	#>
	
    [CmdletBinding()]
    param (
        [parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
        [Alias("ServerInstance", "SqlServer")]
        [object[]]$SqlInstance,
        [System.Management.Automation.PSCredential]$SqlCredential,
        [switch]$Silent
    )
	
	 dynamicparam { if ($SqlInstance) { Get-ParamSqlAgentCategories -SqlServer $SqlInstance[0] -SqlCredential $SqlCredential } }
	
    begin {
        $jobcategories = $psboundparameters.JobCategories
    }
	
    process {
        foreach ($instance in $SqlInstance) {
            Write-Message -Level Verbose -Message "Attempting to connect to $instance"
			
            try {
                $server = Connect-SqlServer -SqlServer $instance -SqlCredential $SqlCredential
            }
            catch {
                Stop-Function -Message "Can't connect to $instance or access denied. Skipping." -Continue
            }
			
			$categories = $server.JobServer.JobCategories
			
            if ($jobcategories) {
                $categories = $categories | Where-Object { $_.Name -in $jobcategories }
            }
			
            foreach ($object in $categories) {
		Write-Message -Level Verbose -Message "Processing $object"
                Add-Member -InputObject $object -MemberType NoteProperty ComputerName -value $server.NetName
                Add-Member -InputObject $object -MemberType NoteProperty InstanceName -value $server.ServiceName
                Add-Member -InputObject $object -MemberType NoteProperty SqlInstance -value $server.DomainInstanceName
				
		# Select all of the columns you'd like to show
                Select-DefaultView -InputObject $object -Property ComputerName, InstanceName, SqlInstance, ID, Name, Whatever, Whatever2
            } #foreach object
        } #foreach instance
    } # process
} #function