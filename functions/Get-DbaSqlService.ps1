Function Get-DbaSqlService {
<#
    .SYNOPSIS
    Gets the SQL Server related services on a computer. 

    .DESCRIPTION
    Gets the SQL Server related services on one or more computers.

    Requires Local Admin rights on destination computer(s).

    .PARAMETER ComputerName
    The SQL Server (or server in general) that you're connecting to. This command handles named instances.

    .PARAMETER InstanceName
    Only returns services that belong to the specific instances.
    
    .PARAMETER Credential
    Credential object used to connect to the computer as a different user.
    
    .PARAMETER Type
    Use -Type to collect only services of the desired SqlServiceType.
    Can be one of the following: "Agent","Browser","Engine","FullText","SSAS","SSIS","SSRS","AnalysisServer",
    	"ReportServer","Search","SqlAgent","SqlBrowser","SqlServer","SqlServerIntegrationService"

    .PARAMETER Silent
		Use this switch to disable any kind of verbose messages
    
    .NOTES
    Author: Klaas Vandenberghe ( @PowerDBAKlaas )

    dbatools PowerShell module (https://dbatools.io)
    Copyright (C) 2016 Chrissy LeMaire
    This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
    This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
    You should have received a copy of the GNU General Public License along with this program. If not, see http://www.gnu.org/licenses/.

    .LINK
    https://dbatools.io/Get-DbaSqlService

    .EXAMPLE
    Get-DbaSqlService -ComputerName sqlserver2014a

    Gets the SQL Server related services on computer sqlserver2014a.

    .EXAMPLE   
    'sql1','sql2','sql3' | Get-DbaSqlService

    Gets the SQL Server related services on computers sql1, sql2 and sql3.

    .EXAMPLE
    Get-DbaSqlService -ComputerName sql1,sql2 | Out-Gridview

    Gets the SQL Server related services on computers sql1 and sql2, and shows them in a grid view.

    .EXAMPLE
    Get-DbaSqlService -ComputerName $MyServers -Type SSRS

    Gets the SQL Server related services of type "SSRS" (Reporting Services) on computers in the variable MyServers.
    
    .EXAMPLE
    $services = Get-DbaSqlService -ComputerName sql1 -Type Agent,Engine
    $services | Foreach-Object { $_.ChangeStartMode('Manual') }

    Gets the SQL Server related services of types Sql Agent and DB Engine on computer sql1 and changes their startup mode to 'Manual'.

#>
	[CmdletBinding()]
	Param (
		[parameter(ValueFromPipeline = $true)]
		[Alias("cn", "host", "Server")]
		[DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME,
		[Alias("Instance")]
		[string[]]$InstanceName,
		[PSCredential]$Credential,
		[ValidateSet("Agent", "Browser", "Engine", "FullText", "SSAS", "SSIS", "SSRS", "AnalysisServer", "ReportServer", "FullTextFilter Daemon Launcher", "FullText Search", "SqlAgent", "SqlBrowser", "SqlServer", "SqlServerIntegrationService")]
		[string[]]$Type,
		[switch]$Silent
	)
	
	BEGIN {
		
		#Dictionary to transform service type IDs into the names from Microsoft.SqlServer.Management.Smo.Wmi.ManagedComputer.Services.Type
		$ServiceIdMap = @(
			@{ Name = "SqlServer"; Id = 1 },
			@{ Name = "SqlAgent"; Id = 2 },
			@{ Name = "FullText Search"; Id = 3 },
			@{ Name = "SqlServerIntegrationService"; Id = 4 },
			@{ Name = "AnalysisServer"; Id = 5 },
			@{ Name = "ReportServer"; Id = 6 },
			@{ Name = "SqlBrowser"; Id = 7 },
			@{ Name = "Unknown"; Id =  8 },
			@{ Name = "FullTextFilter Daemon Launcher"; Id = 9 }
		)
		if ($Type) {
			$TypeClause = ""
			foreach ($itemType in $Type) {
				# Replacing custom types with the canonical names
				$itemType = switch ($itemType) {
					"Agent" { "SqlAgent" }
					"Browser" { "SqlBrowser" }
					"Engine" { "SqlServer" }
					"FullText" { "FullText Search" }
					"SSAS" { "AnalysisServer" }
					"SSIS" { "SqlServerIntegrationService" }
					"SSRS" { "ReportServer" }
					default { $_ }
				}
				
				foreach ($id in ($ServiceIdMap | Where-Object { $_.Name -eq $itemType }).Id) {
					if ($TypeClause) { $TypeClause += ' OR ' }
					$TypeClause += "SQLServiceType = $id"
				}
			}
		}
		else {
			$TypeClause = "SQLServiceType > 0"
		}
	}
	PROCESS {
		foreach ($Computer in $ComputerName.ComputerName) {
			$Server = Resolve-DbaNetworkName -ComputerName $Computer -Credential $credential
			if ($Server.ComputerName) {
				$Computer = $server.ComputerName
				Write-Message -Level Verbose -Message "Getting SQL Server namespace on $Computer"
				$namespace = Get-DbaCmObject -ComputerName $Computer -NameSpace root\Microsoft\SQLServer -Query "Select * FROM __NAMESPACE WHERE Name Like 'ComputerManagement%'" -ErrorAction SilentlyContinue |
				Where-Object { (Get-DbaCmObject -ComputerName $Computer -Namespace $("root\Microsoft\SQLServer\" + $_.Name) -Query "SELECT * FROM SqlService" -ErrorAction SilentlyContinue).count -gt 0 } |
				Sort-Object Name -Descending | Select-Object -First 1
				if ($namespace.Name) {
					Write-Message -Level Verbose -Message "Getting Cim class SqlService in Namespace $($namespace.Name) on $Computer"
					try {
						$services = Get-DbaCmObject -ComputerName $Computer -Namespace $("root\Microsoft\SQLServer\" + $namespace.Name) -Query "SELECT * FROM SqlService WHERE $TypeClause" -ErrorAction SilentlyContinue
						Write-Message -Level Verbose -Silent $Silent -Message "Creating output objects"
						ForEach ($service in $services) {
							Add-Member -Force -InputObject $service -MemberType NoteProperty -Name ComputerName -Value $service.HostName
							Add-Member -Force -InputObject $service -MemberType NoteProperty -Name ServiceType -Value ($ServiceIdMap | Where-Object { $_.Id -contains $service.SQLServiceType }).Name
							Add-Member -Force -InputObject $service -MemberType NoteProperty -Name State -Value $(switch ($service.State) { 1 { 'Stopped' } 2 { 'Start Pending' }  3 { 'Stop Pending' } 4 { 'Running' } })
							Add-Member -Force -InputObject $service -MemberType NoteProperty -Name StartMode -Value $(switch ($service.StartMode) { 1 { 'Unknown' } 2 { 'Automatic' }  3 { 'Manual' } 4 { 'Disabled' } })
							
							if ($service.ServiceName -in ("MSSQLSERVER", "SQLSERVERAGENT", "ReportServer", "MSSQLServerOLAPService")) {
								$instance = "MSSQLSERVER"
							}
							else {
								if ($service.ServiceType -in @("SqlAgent", "SqlServer", "ReportServer", "AnalysisServer")) {
									if ($service.ServiceName.indexof('$') -ge 0) {
										$instance = $service.ServiceName.split('$')[1]
									}
									else {
										$instance = "Unknown"
									}
								}
								else {
									$instance = ""
								}
							}
							$priority = switch ($service.ServiceType) {
								"SqlAgent" { 200 }
								"SqlServer"{ 300 }
								default { 100 }
							}
							#If only specific instances are selected
							if (!$InstanceName -or $instance -in $InstanceName) {
								#Add other properties and methods
								Add-Member -Force -InputObject $service -NotePropertyName InstanceName -NotePropertyValue $instance
								Add-Member -Force -InputObject $service -NotePropertyName ServicePriority -NotePropertyValue $priority
								Add-Member -Force -InputObject $service -MemberType ScriptMethod -Name Stop -Value { $this | Stop-DbaSqlService }
								Add-Member -Force -InputObject $service -MemberType ScriptMethod -Name Start -Value { $this | Start-DbaSqlService }
								Add-Member -Force -InputObject $service -MemberType ScriptMethod -Name Restart -Value { $this | Restart-DbaSqlService }
								Add-Member -Force -InputObject $service -MemberType ScriptMethod -Name ChangeStartMode -Value {
									Param ([string]$Mode)
									$this | Change-DBASqlServiceStartupMode -Mode $Mode -ErrorAction Stop
									$this.StartMode = $Mode
								}
							
								Select-DefaultView -InputObject $service -Property ComputerName, ServiceName, ServiceType, InstanceName, DisplayName, State, StartMode -TypeName DbaSqlService
							}
						}
					}
					catch {
						Write-Message -Level Warning -Message "No Sql Services found on $Computer"
					}
				}
				else {
					Write-Message -Level Warning -Message "No ComputerManagement Namespace on $Computer. Please note that this function is available from SQL 2005 up."
				}
			}
			else {
				Write-Message -Level Warning -Message "Failed to connect to $Computer"
			}
		}
	}
}