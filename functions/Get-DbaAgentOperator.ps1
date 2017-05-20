FUNCTION Get-DbaAgentOperator {
	<#
	.SYNOPSIS
	Returns all SQL Agent operators on a SQL Server Agent.

	.DESCRIPTION
	This function returns SQL Agent operators.

	.PARAMETER SqlInstance
	SQLServer name or SMO object representing the SQL Server to connect to.
	This can be a collection and receive pipeline input.

	.PARAMETER SqlCredential
	PSCredential object to connect as. If not specified, currend Windows login will be used.

	.PARAMETER Silent
	Use this switch to disable any kind of verbose messages

	.NOTES
	Author: Klaas Vandenberghe ( @PowerDBAKlaas )
	Tags: Agent, SMO
	Website: https://dbatools.io
	Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
	License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

	.LINK
	https://dbatools.io/Get-DbaAgentOperator

	.EXAMPLE
	Get-DbaAgentOperator -SqlInstance ServerA,ServerB\instanceB
	Returns any SQL Agent operators on serverA and serverB\instanceB

	.EXAMPLE
	'serverA','serverB\instanceB' | Get-DbaAgentOperator
	Returns all SQL Agent operators  on serverA and serverB\instanceB

	#>
	
	[CmdletBinding()]
	Param (
		[parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[PSCredential][System.Management.Automation.CredentialAttribute()]
		$SqlCredential,
		[switch]$Silent
	)
	process {
		foreach ($instance in $SqlInstance) {
			try {
				Write-Message -Level Verbose -Message "Connecting to $instance"
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
			}
			catch {
				Stop-Function -Message "Failed to connect to $instance : $($_.Exception.Message)" -Continue -Target $instance -InnerErrorRecord $_
			}
			
			Write-Message -Level Verbose -Message "Getting Edition from $server"
			Write-Message -Level Verbose -Message "$server is a $($server.Edition)"
			
			if ($server.Edition -like 'Express*') {
				Stop-Function -Message "There is no SQL Agent on $server, it's a $($server.Edition)" -Continue -Target $server
			}
			
			$defaults = "ComputerName", "SqlInstance", "InstanceName", "Name", "ID", "Enabled as IsEnabled", "EmailAddress", "LastEmail"
			$operators = $server.Jobserver.operators
			
			foreach ($operator in $operators) {
				
				$jobs = $server.JobServer.jobs | Where-Object { $_.OperatorToEmail, $_.OperatorToNetSend, $_.OperatorToPage -contains $operator.Name }
				$lastemail = [dbadatetime]$operator.LastEmailDate
				
				Add-Member -InputObject $operator -MemberType NoteProperty -Name ComputerName -Value $server.NetName
				Add-Member -InputObject $operator -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
				Add-Member -InputObject $operator -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName
				Add-Member -InputObject $operator -MemberType NoteProperty -Name RelatedJobs -Value $jobs
				Add-Member -InputObject $operator -MemberType NoteProperty -Name LastEmail -Value $lastemail
				Select-DefaultView -InputObject $operator -Property $defaults
			}
		}
	}
}
