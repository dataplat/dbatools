Function Get-DbaSqlService
{
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
		[Alias("cn","host","Server")]
			[string[]]$ComputerName = $env:COMPUTERNAME,
		[Alias("Instance")]
			[string[]]$InstanceName,
			[PSCredential] $Credential,
		[ValidateSet("Agent","Browser","Engine","FullText","SSAS","SSIS","SSRS","AnalysisServer","ReportServer","Search","SqlAgent","SqlBrowser","SqlServer","SqlServerIntegrationService")]
			[string[]]$Type,
			[switch]$Silent
	)

	BEGIN
	{
		function ParseConnectionString([string[]]$connectionString) {
			function RunSplit ($SplitString, $Pre, $Delimiter) {
				foreach ($i in 0..($SplitString.Split($Delimiter).Length - 1)) { 
					@{ 
						Pre = switch($i) { 0 { $Pre } default { $Delimiter } }
						Value = $SplitString.Split($Delimiter)[$i]
					}
				}
			}
			$connectionString | Foreach-Object { 
				#find tokens that start from "\" (instance names) and "," (port number)
				$tokens = RunSplit $_ "" "\"| Foreach-Object { RunSplit $_.Value $_.Pre "," }
				[pscustomobject]@{
					ComputerName = ($tokens | Where-Object { $_.Pre -eq "" }).Value
					InstanceName = ($tokens | Where-Object { $_.Pre -eq "\" }).Value
					Port = ($tokens | Where-Object { $_.Pre -eq "," }).Value
				}
			}
		}
		$FunctionName = (Get-PSCallstack)[0].Command
		#Parse computer and instance names if the parameters came as a full instance name: server\instance
		$ComputerName = (ParseConnectionString $ComputerName).ComputerName | Sort-Object -Unique
		
		$ServiceIdMap = @(
			@{Name = "SqlAgent"; Id = 2},
			@{Name = "SqlBrowser"; Id = 7}
			@{Name = "SqlServer"; Id = 1}
			@{Name = "Search"; Id = 3,9}
			@{Name = "AnalysisServer"; Id = 5}
			@{Name = "SqlServerIntegrationService"; Id = 4}
			@{Name = "ReportServer"; Id = 6}
		)
		if ($Type) {
			$TypeClause = ""
			foreach ($itemType in $Type) {
				$itemType = switch ($itemType) {
					"Agent" {"SqlAgent"}
					"Browser" {"SqlBrowser"}
					"Engine" {"SqlServer"}
					"FullText" {"Search"}
					"SSAS" {"AnalysisServer"}
					"SSIS" {"SqlServerIntegrationService"}
					"SSRS" {"ReportServer"}
					default {$_}
				}
				
				foreach ($id in ($ServiceIdMap|Where {$_.Name -eq $itemType}).Id) {
					if ($TypeClause) { $TypeClause += ' OR ' }
					$TypeClause += "SQLServiceType = $id"
				}
			}
		}
		else {
			$TypeClause = "SQLServiceType > 0"
		}
	}
	PROCESS
	{
		foreach ( $Computer in $ComputerName ) {
			$Server = Resolve-DbaNetworkName -ComputerName $Computer -Credential $credential
			if ( $Server.ComputerName )	{
				$Computer = $server.ComputerName
				Write-Message -Level Verbose -Silent $Silent -Message "Getting SQL Server namespace on $Computer via CIM (WSMan)"
				$namespace = Get-CimInstance -ComputerName $Computer -NameSpace root\Microsoft\SQLServer -ClassName "__NAMESPACE" -Filter "Name Like 'ComputerManagement%'" -ErrorAction SilentlyContinue |
					Where-Object {(Get-CimInstance -ComputerName $Computer -Namespace $("root\Microsoft\SQLServer\" + $_.Name) -Query "SELECT * FROM SqlService" -ErrorAction SilentlyContinue).count -gt 0} |
					Sort-Object Name -Descending | Select-Object -First 1
				if ( $namespace.Name ) {
					Write-Message -Level Verbose -Silent $Silent -Message "Getting Cim class SqlService in Namespace $($namespace.Name) on $Computer via CIM (WSMan)"
					try
					{
						$CimInstance = Get-CimInstance -ComputerName $Computer -Namespace $("root\Microsoft\SQLServer\" + $namespace.Name) -Query "SELECT * FROM SqlService WHERE $TypeClause" -ErrorAction SilentlyContinue
					}
					catch
					{
						Write-Message -Level Verbose -Silent $Silent -Message "No Sql Services found on $Computer via CIM (WSMan)"
						continue
					}
				}
				else {
					Write-Message -Level Verbose -Silent $Silent -Message "Getting computer information from $Computer via CIMsession (DCOM)"
					$sessionoption = New-CimSessionOption -Protocol DCOM
					$CIMsession = New-CimSession -ComputerName $Computer -SessionOption $sessionoption -ErrorAction SilentlyContinue -Credential $Credential
					if ( $CIMSession ) {
						Write-Message -Level Verbose -Silent $Silent -Message "Get ComputerManagement Namespace in CIMsession on $Computer with protocol DCom."
						$namespace = Get-CimInstance -CimSession $CIMsession -NameSpace root\Microsoft\SQLServer -ClassName "__NAMESPACE" -Filter "Name Like 'ComputerManagement%'" -ErrorAction SilentlyContinue |
						Where-Object {(Get-CimInstance -CimSession $CIMsession -Namespace $("root\Microsoft\SQLServer\" + $_.Name) -Query "SELECT * FROM SqlService" -ErrorAction SilentlyContinue).count -gt 0} |
						Sort-Object Name -Descending | Select-Object -First 1
					}
					else {
						Write-Message -Level Verbose -Silent $Silent -Message "Can't create CIMsession via DCom on $Computer"
						continue
					}
					if ( $namespace.Name ) {
						Write-Message -Level Verbose -Silent $Silent -Message "Getting Cim class SqlService in Namespace $($namespace.Name) on $Computer via CIM (DCOM)"
						try {
								$CimInstance = Get-CimInstance -CimSession $CIMsession -Namespace $("root\Microsoft\SQLServer\" + $namespace.Name) -Query "SELECT * FROM SqlService WHERE $TypeClause" -ErrorAction SilentlyContinue
						}
						catch {
							Write-Message -Level Warning -Silent $Silent -Message "No Sql Services found on $Computer via CIM (DCOM)"
							continue
						}
					}
					else {
						Write-Message -Level Warning -Silent $Silent -Message "No ComputerManagement Namespace on $Computer. Please note that this function is available from SQL 2005 up."
						continue
					}
				}
			}
			else {
				Write-Message -Level Warning -Silent $Silent -Message "Failed to connect to $Computer"
			}
			#Process Cim objects
			Write-Message -Level Verbose -Silent $Silent -Message "Creating output objects"
			$CimInstance | ForEach-Object {
				$CimObject = $_
				$outObject = [PSCustomObject]@{
						ComputerName = $_.HostName
						ServiceName = $_.ServiceName
						DisplayName = $_.DisplayName
						StartName = $_.StartName
						ServiceType = ($ServiceIdMap | Where-Object {$_.Id -contains $CimObject.SQLServiceType}).Name
						State = switch($_.State){ 1 {'Stopped'} 2 {'Start Pending'}  3 {'Stop Pending' } 4 {'Running'}}
						StartMode = switch($_.StartMode){ 1 {'Unknown'} 2 {'Automatic'}  3 {'Manual' } 4 {'Disabled'}}
				}
				if ($outObject.ServiceName -in ("MSSQLSERVER","SQLSERVERAGENT","ReportServer","MSSQLServerOLAPService")) {
					$instance = "MSSQLSERVER"
				}
				else {
					if ($outObject.ServiceType -in @("SqlAgent","SqlServer","ReportServer","AnalysisServer")) {
						if ($outObject.ServiceName.indexof('$') -ge 0) {
							$instance = $outObject.ServiceName.split('$')[1]
						}
						else {
							$instance = "UNKNOWN!"
						}
					}
					else {
						$instance = ""
					}
				}
				switch ($outObject.ServiceType) {
					"SqlAgent" { $priority = 200 }
					"SqlServer"{ $priority = 300 }
					default { $priority = 100 }
				}
				#Add custom properties and methods
				Add-Member -Force -InputObject $outObject -NotePropertyName InstanceName -NotePropertyValue $instance
				Add-Member -Force -InputObject $outObject -NotePropertyName ServicePriority -NotePropertyValue $priority
				Add-Member -Force -InputObject $outObject -MemberType ScriptMethod -Name Stop -Value {$this|Stop-DbaSqlService}
				Add-Member -Force -InputObject $outObject -MemberType ScriptMethod -Name Start -Value {$this|Start-DbaSqlService}
				Add-Member -Force -InputObject $outObject -MemberType ScriptMethod -Name Restart -Value { $this|Restart-DbaSqlService }
				Add-Member -Force -InputObject $outObject -MemberType ScriptMethod -Name ChangeStartMode -Value {
					Param ([string]$Mode) 
					$this|Change-DBASqlServiceStartupMode -Mode $Mode -ErrorAction Stop
					$this.StartMode = $Mode
				}
				if (!$InstanceName -or $outObject.InstanceName -in $instanceName) {
					Select-DefaultView -InputObject $outObject -Property ComputerName, ServiceName, ServiceType, InstanceName, DisplayName, State, StartMode -TypeName DbaSqlService
				}
			}
			if ( $CIMsession ) { Remove-CimSession $CIMsession }
		}
	}
}
