Function Restart-DbaSqlService {
<#
    .SYNOPSIS
    Restarts SQL Server services on a computer. 

    .DESCRIPTION
    Restarts the SQL Server related services on one or more computers. Will follow SQL Server service dependencies.

    Requires Local Admin rights on destination computer(s).

    .PARAMETER ComputerName
    The SQL Server (or server in general) that you're connecting to. This command handles named instances.

    .PARAMETER InstanceName
    Only affects services that belong to the specific instances.
    
    .PARAMETER Credential
    Credential object used to connect to the computer as a different user.
    
    .PARAMETER Type
    Use -Type to collect only services of the desired SqlServiceType.
    Can be one of the following: "Agent","Browser","Engine","FullText","SSAS","SSIS","SSRS","AnalysisServer",
    	"ReportServer","Search","SqlAgent","SqlBrowser","SqlServer","SqlServerIntegrationService"
    
    .PARAMETER Timeout
    How long to wait for the start/stop request completion before moving on.
    
    .PARAMETER ServiceCollection
    A collection of services from Get-DbaSqlService
    
    .PARAMETER Silent
    Prevent any output.

    .NOTES
    Author: Kirill Kravtsov( @nvarscar )

    dbatools PowerShell module (https://dbatools.io)
    Copyright (C) 2017 Chrissy LeMaire
    This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
    This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.
    You should have received a copy of the GNU General Public License along with this program. If not, see http://www.gnu.org/licenses/.

    .LINK
    https://dbatools.io/Restart-DbaSqlService

    .EXAMPLE
    Restart-DbaSqlService -ComputerName sqlserver2014a

    Restarts the SQL Server related services on computer sqlserver2014a.

    .EXAMPLE   
    'sql1','sql2','sql3'| Get-DbaSqlService | Restart-DbaSqlService

    Gets the SQL Server related services on computers sql1, sql2 and sql3 and restarts them.

    .EXAMPLE
    Restart-DbaSqlService -ComputerName sql1,sql2 -Instance MSSQLSERVER

    Restarts the SQL Server services related to the default instance MSSQLSERVER on computers sql1 and sql2.

    .EXAMPLE
    Restart-DbaSqlService -ComputerName $MyServers -Type SSRS

    Restarts the SQL Server related services of type "SSRS" (Reporting Services) on computers in the variable MyServers.

#>
	[CmdletBinding(DefaultParameterSetName = "Server", SupportsShouldProcess = $true)]
	Param (
		[Parameter(ParameterSetName = "Server", Position = 1)]
		[Alias("cn", "host", "Server")]
		[string[]]$ComputerName = $env:COMPUTERNAME,
		[Alias("Instance")]
		[string[]]$InstanceName,
		[ValidateSet("Agent", "Browser", "Engine", "FullText", "SSAS", "SSIS", "SSRS", "AnalysisServer", "ReportServer", "Search", "SqlAgent", "SqlBrowser", "SqlServer", "SqlServerIntegrationService")]
		[string[]]$Type,
		[parameter(ValueFromPipeline = $true, Mandatory = $true, ParameterSetName = "Service")]
		[object[]]$ServiceCollection,
		[int]$Timeout = 30,
		[PSCredential]$Credential,
		[switch]$Silent
	)
	begin {
		if ($Type) {
			foreach ($i in 0 .. ($Type.Length - 1)) {
				$Type[$i] = switch ($Type[$i]) {
					"Agent" { "SqlAgent" }
					"Browser" { "SqlBrowser" }
					"Engine" { "SqlServer" }
					"FullText" { "Search" }
					"SSAS" { "AnalysisServer" }
					"SSIS" { "SqlServerIntegrationService" }
					"SSRS" { "ReportServer" }
					default { $_ }
				}
			}
		}
		$ProcessArray = @()
		if ($PsCmdlet.ParameterSetName -eq "Server") {
			$parameters = @{ }
			if ($ComputerName) { $parameters.ComputerName = $ComputerName }
			if ($InstanceName) { $parameters.InstanceName = $InstanceName }
			if ($Type) { $parameters.Type = $Type }
			if ($Credential) { $parameters.Credential = $Credential }
			$ServiceCollection = Get-DbaSqlService @parameters
		}
	}
	process {
		#Get all the objects from the pipeline before proceeding
		$ProcessArray += $ServiceCollection
	}
	end {
		$ProcessArray = $ProcessArray | Where-Object { (!$InstanceName -or $_.InstanceName -in $InstanceName) -and (!$Type -or $_.ServiceType -in $Type) }
		if ($ProcessArray) {
			Update-DbaSqlServiceStatus -ServiceCollection $ProcessArray -Action 'stop' -Timeout $Timeout -Silent $Silent
			Update-DbaSqlServiceStatus -ServiceCollection $ProcessArray -Action 'start' -Timeout $Timeout -Silent $Silent
		}
		else { Write-Message -Level Warning -Silent $Silent -Message "No SQL Server services found with current parameters." }
	}
}
