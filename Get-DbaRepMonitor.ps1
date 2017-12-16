function Get-DbaRepMonitor {
    <# 
    .SYNOPSIS 
        Gets the information about a replication monitor for a given SQL Server instance.
    
	.DESCRIPTION 
        This function locates and enumerates monitor information for a given SQL Server instance.
    
	.PARAMETER SqlInstance
        Allows you to specify a comma separated list of servers to query.
    
	.PARAMETER SqlCredential
        Allows you to login to servers using alternative credentials.

	.PARAMETER Type
		Specify the type of monitor. By default, all types are returned. Options include DistributionAgent, LogReaderAgent, MergeAgent, MiscellaneousAgent, Publisher, SnapshotAgent
	
	.PARAMETER EnableException 
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
        
	.NOTES 
        Tags: Replication
        Website: https://dbatools.io
        Copyright: (C) Chrissy LeMaire, clemaire@gmail.com
        License: GNU GPL v3 https://opensource.org/licenses/GPL-3.0
    
	.LINK 
        https://dbatools.io/Get-DbaRepMonitor
    
	.EXAMPLE   
        Get-DbaRepMonitor -SqlInstance sql2008, sqlserver2012
        Retrieve monitor information for servers sql2008 and sqlserver2012.
    #>
	[CmdletBinding(DefaultParameterSetName = "Default")]
	param (
		[parameter(Mandatory, ParameterSetName = "instance")]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[parameter(Mandatory = $false)]
		[Alias("Credential")]
		[PSCredential]$SqlCredential,
		[ValidateSet("All", "DistributionAgent", "LogReaderAgent", "MergeAgent", "MiscellaneousAgent", "Publisher", "QueueReaderAgent", "SnapshotAgent")]
		[string[]]$Type = "All",
		[switch]$EnableException
	)
	process {
		
		foreach ($instance in $SqlInstance) {
			Write-Message -Level Verbose -Message "Attempting to connect to $instance"
			
			# connect to the instance
			try {
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 9
			}
			catch {
				Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
			}
			
			Write-Message -Level Verbose -Message "Attempting to retrieve monitor information from $instance"
			
			# Connect to the monitor of the instance
			try {
				$sourceSqlConn = $server.ConnectionContext.SqlConnectionObject
				$monitorcollection += New-Object Microsoft.SqlServer.Replication.ReplicationMonitor $sourceSqlConn
			}
			catch {
				Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
			}
		}
		
		foreach ($monitor in $monitorcollection) {
			if ($Type -contains "All" -or $Type -contains "DistributionAgent") {
				foreach ($enum in ($monitor.EnumDistributionAgents()).Tables) {
					Add-Member -Force -InputObject $enum -MemberType NoteProperty -Name ComputerName -Value $server.NetName
					Add-Member -Force -InputObject $enum -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
					Add-Member -Force -InputObject $enum -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName
					Add-Member -Force -InputObject $enum -MemberType NoteProperty -Name Type -Value "DistributionAgent"
					Select-DefaultView -InputObject $enum -Property ComputerName, InstanceName, SqlInstance, Type, 'dbname as Database', Status, Publisher, 'publisher_db as PublisherDatabase', Publication, Subscriber, 'subscriber_db as SubscriberDatabase', StartTime, Time, Duration, Comments
				}
			}
			
			<#
			if ($Type -contains "All" -or $Type -contains "ErrorRecord") {
				foreach ($enum in ($monitor.EnumErrorRecords()).Tables) {
					Add-Member -Force -InputObject $enum -MemberType NoteProperty -Name ComputerName -Value $server.NetName
					Add-Member -Force -InputObject $enum -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
					Add-Member -Force -InputObject $enum -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName
					Add-Member -Force -InputObject $enum -MemberType NoteProperty -Name Type -Value "ErrorRecord"
					Select-DefaultView -InputObject $enum -Property ComputerName, InstanceName, SqlInstance, Type, 'dbname as Database', Status, Publisher, 'publisher_db as PublisherDatabase', Publication, Subscriber, 'subscriber_db as SubscriberDatabase', StartTime, Time, Duration, Comments
				}
			}
			#>
			
			if ($Type -contains "All" -or $Type -contains "LogReaderAgent") {
				foreach ($enum in ($monitor.EnumLogReaderAgents()).Tables) {
					Add-Member -Force -InputObject $enum -MemberType NoteProperty -Name ComputerName -Value $server.NetName
					Add-Member -Force -InputObject $enum -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
					Add-Member -Force -InputObject $enum -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName
					Add-Member -Force -InputObject $enum -MemberType NoteProperty -Name Type -Value "LogReaderAgent"
					Select-DefaultView -InputObject $enum -Property ComputerName, InstanceName, SqlInstance, Type, 'dbname as Database', Status, Publisher, 'publisher_db as PublisherDatabase', Publication, Subscriber, 'subscriber_db as SubscriberDatabase', StartTime, Time, Duration, Comments
				}
			}
			
			if ($Type -contains "All" -or $Type -contains "MergeAgent") {
				foreach ($enum in ($monitor.EnumMergeAgents()).Tables) {
					Add-Member -Force -InputObject $enum -MemberType NoteProperty -Name ComputerName -Value $server.NetName
					Add-Member -Force -InputObject $enum -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
					Add-Member -Force -InputObject $enum -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName
					Add-Member -Force -InputObject $enum -MemberType NoteProperty -Name Type -Value "MergeAgent"
					Select-DefaultView -InputObject $enum -Property ComputerName, InstanceName, SqlInstance, Type, 'dbname as Database', Status, Publisher, 'publisher_db as PublisherDatabase', Publication, Subscriber, 'subscriber_db as SubscriberDatabase', StartTime, Time, Duration, Comments
				}
			}
			
			if ($Type -contains "All" -or $Type -contains "MiscellaneousAgent") {
				foreach ($enum in ($monitor.EnumMiscellaneousAgents()).Tables) {
					Add-Member -Force -InputObject $enum -MemberType NoteProperty -Name ComputerName -Value $server.NetName
					Add-Member -Force -InputObject $enum -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
					Add-Member -Force -InputObject $enum -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName
					Add-Member -Force -InputObject $enum -MemberType NoteProperty -Name Type -Value "MiscellaneousAgent"
					Select-DefaultView -InputObject $enum -Property ComputerName, InstanceName, SqlInstance, Type, 'dbname as Database', Status, Publisher, 'publisher_db as PublisherDatabase', Publication, Subscriber, 'subscriber_db as SubscriberDatabase', StartTime, Time, Duration, Comments
				}
			}
			
			if ($Type -contains "All" -or $Type -contains "Publisher") {
				foreach ($enum in ($monitor.EnumPublishers()).Tables) {
					Add-Member -Force -InputObject $enum -MemberType NoteProperty -Name ComputerName -Value $server.NetName
					Add-Member -Force -InputObject $enum -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
					Add-Member -Force -InputObject $enum -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName
					Add-Member -Force -InputObject $enum -MemberType NoteProperty -Name Type -Value "Publisher"
					Select-DefaultView -InputObject $enum -Property ComputerName, InstanceName, SqlInstance, Type, 'dbname as Database', Status, Publisher, 'publisher_db as PublisherDatabase', Publication, Subscriber, 'subscriber_db as SubscriberDatabase', StartTime, Time, Duration, Comments
				}
				try {
					foreach ($enum in ($monitor.EnumPublishers2()).Tables) {
						Add-Member -Force -InputObject $enum -MemberType NoteProperty -Name ComputerName -Value $server.NetName
						Add-Member -Force -InputObject $enum -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
						Add-Member -Force -InputObject $enum -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName
						Add-Member -Force -InputObject $enum -MemberType NoteProperty -Name Type -Value "Publisher2"
						Select-DefaultView -InputObject $enum -Property ComputerName, InstanceName, SqlInstance, Type, 'dbname as Database', Status, Publisher, 'publisher_db as PublisherDatabase', Publication, Subscriber, 'subscriber_db as SubscriberDatabase', StartTime, Time, Duration, Comments
					}
				}
				catch { }
			}
			
			<#
			if ($Type -contains "All" -or $Type -contains "QueueReaderAgent") {
				
				foreach ($enum in ($monitor.EnumQueueReaderAgentSessionDetails()).Tables) {
					Add-Member -Force -InputObject $enum -MemberType NoteProperty -Name ComputerName -Value $server.NetName
					Add-Member -Force -InputObject $enum -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
					Add-Member -Force -InputObject $enum -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName
					Add-Member -Force -InputObject $enum -MemberType NoteProperty -Name Type -Value "QueueReaderAgentSessionDetail"
					Select-DefaultView -InputObject $enum -Property ComputerName, InstanceName, SqlInstance, Type, 'dbname as Database', Status, Publisher, 'publisher_db as PublisherDatabase', Publication, Subscriber, 'subscriber_db as SubscriberDatabase', StartTime, Time, Duration, Comments
				}
				
				foreach ($enum in ($monitor.EnumQueueReaderAgentSessions()).Tables) {
					Add-Member -Force -InputObject $enum -MemberType NoteProperty -Name ComputerName -Value $server.NetName
					Add-Member -Force -InputObject $enum -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
					Add-Member -Force -InputObject $enum -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName
					Add-Member -Force -InputObject $enum -MemberType NoteProperty -Name Type -Value "QueueReaderAgentSession"
					Select-DefaultView -InputObject $enum -Property ComputerName, InstanceName, SqlInstance, Type, 'dbname as Database', Status, Publisher, 'publisher_db as PublisherDatabase', Publication, Subscriber, 'subscriber_db as SubscriberDatabase', StartTime, Time, Duration, Comments
				}
			}
			#>
			
			if ($Type -contains "All" -or $Type -contains "SnapshotAgent") {
				foreach ($enum in ($monitor.EnumSnapshotAgents()).Tables) {
					Add-Member -Force -InputObject $enum -MemberType NoteProperty -Name ComputerName -Value $server.NetName
					Add-Member -Force -InputObject $enum -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
					Add-Member -Force -InputObject $enum -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName
					Add-Member -Force -InputObject $enum -MemberType NoteProperty -Name Type -Value "SnapshotAgent"
					Select-DefaultView -InputObject $enum -Property ComputerName, InstanceName, SqlInstance, Type, 'dbname as Database', Status, Publisher, 'publisher_db as PublisherDatabase', Publication, Subscriber, 'subscriber_db as SubscriberDatabase', StartTime, Time, Duration, Comments
				}
			}
			
			#Select-DefaultView -InputObject $monitor -Property ComputerName, InstanceName, SqlInstance, IsPublisher, IsMonitor, DistributionServer, DistributionDatabase, MonitorInstalled, MonitorAvailable, HasRemotePublisher
		}
	}
}