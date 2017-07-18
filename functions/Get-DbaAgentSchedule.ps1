FUNCTION Get-DbaAgentSchedule
{
<#
	.SYNOPSIS
	Returns all SQL Agent Shared Schedules on a SQL Server Agent.

	.DESCRIPTION
	This function returns SQL Agent Shared Schedules.

	.PARAMETER SqlInstance
	SqlInstance name or SMO object representing the SQL Server to connect to.
	This can be a collection and receive pipeline input.

	.PARAMETER SqlCredential
	PSCredential object to connect as. If not specified, current Windows login will be used.

	.PARAMETER Silent
	Use this switch to disable any kind of verbose messages

	.NOTES
	Author: Chris McKeown (@devopsfu), http://www.devopsfu.com
	Tags: Agent, Schedule
	Website: https://dbatools.io
	Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
	License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0

	.LINK
	https://dbatools.io/Get-DbaAgentSchedule

	.EXAMPLE
	Get-DbaAgentSchedule -SqlInstance localhost
	Returns all SQL Agent Shared Schedules on the local default SQL Server instance

	.EXAMPLE
	Get-DbaAgentSchedule -SqlInstance localhost, sql2016
	Returns all SQL Agent Shared Schedules for the local and sql2016 SQL Server instances

#>
	[CmdletBinding()]
	Param (
		[parameter(Position = 0, Mandatory = $true, ValueFromPipeline = $True)]
		[Alias("ServerInstance", "Instance", "SqlServer")]
		[object[]]$SqlInstance,
		[PSCredential]$SqlCredential,
		[switch]$Silent
	)
	
	process {
		foreach ($instance in $SqlInstance) {
			Write-Message -Level Verbose -Message "Attempting to connect to $instance"
			try {
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential
			}
			catch {
				Write-Message -Level Warning -Message "Can't connect to $instance or access denied. Skipping."
				continue
			}

			Write-Message -Level Verbose -Message "Getting Edition from $server"
			Write-Message -Level Verbose -Message "$server is a $($server.Edition)"
			
			if ($server.Edition -like 'Express*') {
				Stop-Function -Message "There is no SQL Agent on $server, it's a $($server.Edition)" -Continue
			}
			
			$defaults = "ComputerName", "InstanceName", "SqlInstance", "Parent", "ActiveEndDate", "ActiveEndTimeOfDay", "ActiveStartDate", "ActiveStartTimeOfDay", "DateCreated", "FrequencyInterval", "FrequencyRecurrenceFactor", "FrequencyRelativeIntervals", "FrequencySubDayInterval", "FrequencySubDayTypes", "FrequencyTypes", "IsEnabled", "JobCount", "ScheduleUid"

			foreach ($schedule in $server.JobServer.SharedSchedules)
			{
				Add-Member -Force -InputObject $schedule -MemberType NoteProperty ComputerName -value $schedule.Parent.Parent.NetName
				Add-Member -Force -InputObject $schedule -MemberType NoteProperty InstanceName -value $schedule.Parent.Parent.ServiceName
				Add-Member -Force -InputObject $schedule -MemberType NoteProperty SqlInstance  -value $schedule.Parent.Parent.DomainInstanceName

				Select-DefaultView -InputObject $schedule -Property $defaults
			}
		}
	}
}
