FUNCTION Get-DbaTraceFlag {
	<#
		.SYNOPSIS
			Gets SQL Trace Flags information for each instance(s) of SQL Server.

		.DESCRIPTION
			The Get-DbaTraceFlag returns connected SMO object for SQL Trace Flags information for each instance(s) of SQL Server.

		.PARAMETER SqlInstance
			SQL Server name or SMO object representing the SQL Server to connect to. This can be a collection and receive pipeline input to allow the function to be executed against multiple SQL Server instances.

		.PARAMETER SqlCredential
			SqlCredential object to connect as. If not specified, current Windows login will be used.

		.PARAMETER TraceFlag
			Use this switch to filter to a specific Trace Flag.

		.PARAMETER Silent
			Use this switch to disable any kind of verbose messages.

		.NOTES
			Tags: Trace, Flag
			Original Author: Kevin Bullen (@sqlpadawan)

			References:  https://msdn.microsoft.com/en-us/library/microsoft.sqlserver.management.smo.server.enumactivecurrentsessiontraceflags(v=sql.120).aspx

			Website: https://dbatools.io
			Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
			License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

		.LINK
			https://dbatools.io/Get-DbaTraceFlag

		.EXAMPLE
			Get-DbaTraceFlag -SqlInstance localhost

			Returns all SQL Trace Flag information on the local default SQL Server instance

		.EXAMPLE
			Get-DbaTraceFlag -SqlInstance localhost, sql2016

			Returns all SQl Trace Flag for the local and sql2016 SQL Server instances

		.EXAMPLE
			Get-DbaTraceFlag -SqlInstance localhost -TraceFlag 4199,3205

			Returns all SQl Trace Flag 4199 and 3205 status for local SQL Server instance
	#>
	[CmdletBinding()]
	param (
		[parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[PSCredential]
		$SqlCredential,
		[object[]]$TraceFlag,
		[switch]$Silent
	)

	process {
		foreach ($instance in $SqlInstance) {
			Write-Verbose "Attempting to connect to $instance"
			try {
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
			}
			catch {
				Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
			}

            $tflags = New-Object System.Data.DataTable;

			$tflags = $server.EnumActiveGlobalTraceFlags();
			
			if ($TraceFlag) {
				$tflags = $tflags | Where-Object TraceFlag -In $TraceFlag
			}
		               
			foreach ($tflag in $tflags) {
                
                #otherwise rowerror, rowstate, blah blah fields added to output.
                $tflagdata = @{'ComputerName' = $server.NetName;
                               'InstanceName' = $server.ServiceName;
                               'SqlInstance' = $server.DomainInstanceName;
                               'TraceFlag' = $tflag.TraceFlag;
                               'Global' = $tflag.Global;
                               'Session' = $tflag.Session;
                               'Status' = $tflag.Status};
                               
                $tflagrow = New-Object psobject -Property $tflagdata
                
                Select-DefaultView -InputObject $tflagrow -Property 'ComputerName','InstanceName','SqlInstance','TraceFlag','Global','Session','Status'

            } 
		}
	}
}
