Function New-DbaSsisCatalog
{
<#
.SYNOPSIS 
Enables the SSIS Catalog on a SQL Server 2012+

.DESCRIPTION
After installing the SQL Server Engine and SSIS you still have to enable the SSIS Catalog. This function will enable the catalog and gives the option of supplying the password. 

.PARAMETER SqlInstance
SQL Server you wish to run the function on.

.PARAMETER SqlCredential
Credenitals used to connect to the SQL Server

.PARAMETER SsisCredential
Required password that will be used for the security key in SSISDB. You must pass in a PowerShell credential - only the password is required for SSIS but PowerShell insists you add a username, so add whatever.

.PARAMETER SsisCatalog
SSIS catalog name. By default, this is SSISDB.	
	
.PARAMETER WhatIf 
Shows what would happen if the command were to run. No actions are actually performed. 

.PARAMETER Confirm 
Prompts you for confirmation before executing any changing operations within the command. 
	
.PARAMETER Silent 
Use this switch to disable any kind of verbose messages

.NOTES 
Author: Stephen Bennett, https://sqlnotesfromtheunderground.wordpress.com/

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/New-DbaSsisCatalog

.EXAMPLE   
New-DbaSsisCatalog -SqlInstance DEV01 -SsisCredential (Get-Credential)

Prompts for username/password - while only password is used, the username must be filled out nevertheless. Then creates the SSIS Catalog on server DEV01 with the specified password. 

#>
	[CmdletBinding(SupportsShouldProcess = $true)]
	Param (
		[parameter(Mandatory = $true, ValueFromPipeline = $true)]
		[Alias("ServerInstance", "SqlServer")]
		[DbaInstanceParameter[]]$SqlInstance,
		[System.Management.Automation.PSCredential]$SqlCredential,
		[parameter(Mandatory = $true)]
		[System.Management.Automation.PSCredential]$SsisCredential,
		[string]$SsisCatalog = "SSISDB",
		[switch]$Silent
	)
	
	process
	{
		foreach ($instance in $SqlInstance)
		{
			Write-Message -Level Verbose -Message "Attempting to connect to $instance"
			
			try
			{
				Write-Message -Level Verbose -Message "Connecting to $instance"
				$server = Connect-SqlInstance -SqlInstance $instance -SqlCredential $sqlcredential
			}
			catch
			{
				Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue
			}
			
			#if SQL 2012 or higher only validate databases with ContainmentType = NONE
			if ($server.versionMajor -lt 10)
			{
				Stop-Function -Message "This version of SQL Server cannot have SSIS catalog" -Continue -Target $instance
			}
			
			## check if SSIS and Engine running on box
			$services = Get-DbaSqlService -ComputerName $server.NetName
			
			$ssisservice = $Services | Where-Object { $_.ServiceType -eq "SSIS" -and $_.State -eq "Running" }
			
			if (-not $ssisservice)
			{
				Stop-Function -Message "SSIS is not running on $instance" -Continue -Target $instance
			}
			
			#if SQL 2012 or higher only validate databases with ContainmentType = NONE
			$clrenabled = Get-DbaSpConfigure -SqlInstance $server | Where-Object ConfigName -eq IsSqlClrEnabled
			
			if (!$clrenabled.RunningValue)
			{
				Stop-Function -Message 'CLR Integration must be enabled.  You can enable it by running Set-DbaSpConfigure -SqlInstance sql2012 -Config IsSqlClrEnabled -Value $true' -Continue -Target $instance
			}
			
			$ssis = New-Object Microsoft.SqlServer.Management.IntegrationServices.IntegrationServices $server
			
			if ($ssis.Catalogs[$SsisCatalog])
			{
				Stop-Function -Message "SSIS Catalog already exists" -Continue -Target $ssis.Catalogs[$SsisCatalog]
			}
			else
			{
				if ($Pscmdlet.ShouldProcess($server, "Creating SSIS catalog: $SsisCatalog"))
				{
					try
					{
						$ssisdb = New-Object Microsoft.SqlServer.Management.IntegrationServices.Catalog ($ssis, $SsisCatalog, $($SsisCredential.GetNetworkCredential().Password))
						$ssisdb.Create()
						
						[pscustomobject]@{
							ComputerName = $server.NetName
							InstanceName = $server.ServiceName
							SqlInstance = $server.DomainInstanceName
							SsisCatalog = $SsisCatalog
							Created = $true
						}
					}
					catch
					{
						Stop-Function -Message "Failed to create SSIS Catalog: $_" -Target $_ -Continue
					}
				}
			}
		}
	}
}
