Function Copy-SqlSpConfigure
{
<#
.SYNOPSIS 
Copy-SqlSpConfigure migrates configuration values from one SQL Server to another. 

.DESCRIPTION
By default, all configuration values are copied. The -Configs parameter is autopopulated for command-line completion and can be used to copy only specific configs.

.PARAMETER Source
Source SQL Server.You must have sysadmin access and server version must be SQL Server version 2000 or greater.

.PARAMETER Destination
Destination Sql Server. You must have sysadmin access and server version must be SQL Server version 2000 or greater.

.PARAMETER SourceSqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$scred = Get-Credential, then pass $scred object to the -SourceSqlCredential parameter. 

Windows Authentication will be used if DestinationSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials. 	
To connect as a different Windows user, run PowerShell as that user.

.PARAMETER DestinationSqlCredential
Allows you to login to servers using SQL Logins as opposed to Windows Auth/Integrated/Trusted. To use:

$dcred = Get-Credential, then pass this $dcred to the -DestinationSqlCredential parameter. 

Windows Authentication will be used if DestinationSqlCredential is not specified. SQL Server does not accept Windows credentials being passed as credentials. 	
To connect as a different Windows user, run PowerShell as that user.

.NOTES 
Author: Chrissy LeMaire (@cl), netnerds.net
Requires: sysadmin access on SQL Servers

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Copy-SqlSpConfigure 

.EXAMPLE   
Copy-SqlSpConfigure -Source sqlserver2014a -Destination sqlcluster

Copies all sp_configure settings from sqlserver2014a to sqlcluster

.EXAMPLE   
Copy-SqlSpConfigure -Source sqlserver2014a -Destination sqlcluster -Configs DefaultBackupCompression, IsSqlClrEnabled -SourceSqlCredential $cred -Force

Updates the values for two configs, the  IsSqlClrEnabled and DefaultBackupCompression, from sqlserver2014a to sqlcluster, using SQL credentials for sqlserver2014a and Windows credentials for sqlcluster.

.EXAMPLE   
Copy-SqlSpConfigure -Source sqlserver2014a -Destination sqlcluster -WhatIf

Shows what would happen if the command were executed.
#>
    [CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
    param (
	    [parameter(Mandatory = $true)]
	    [object]$Source,
	    [parameter(Mandatory = $true)]
	    [object]$Destination,
	    [System.Management.Automation.PSCredential]$SourceSqlCredential,
	    [System.Management.Automation.PSCredential]$DestinationSqlCredential
    )
	
    DynamicParam { if ($source) { return (Get-ParamSqlServerConfigs -SqlServer $Source -SqlCredential $SourceSqlCredential) } }
	
    BEGIN
    {
	    $configs = $psboundparameters.Configs
		
	    $sourceserver = Connect-SqlServer -SqlServer $Source -SqlCredential $SourceSqlCredential
	    $destserver = Connect-SqlServer -SqlServer $Destination -SqlCredential $DestinationSqlCredential
		
	    $source = $sourceserver.DomainInstanceName
	    $destination = $destserver.DomainInstanceName
    }
    PROCESS
    {
	    If ($Pscmdlet.ShouldProcess("both servers", "Updating sp_configure to show advanced options"))
	    {
		    $sourceserver.Configuration.ShowAdvancedOptions.ConfigValue = $true
		    $sourceserver.ConnectionContext.ExecuteNonQuery("RECONFIGURE WITH OVERRIDE") | Out-Null
		    $destserver.Configuration.ShowAdvancedOptions.ConfigValue = $true
		    $destserver.ConnectionContext.ExecuteNonQuery("RECONFIGURE WITH OVERRIDE") | Out-Null
	    }
		
	    $destprops = $destserver.Configuration.Properties
		
	    # crude but i suck with properties
	    $lookups = $sourceserver.Configuration.PsObject.Properties.Name | Where-Object { $_ -notin "Parent", "Properties" }
		
	    $proplookup = @()
	    foreach ($lookup in $lookups)
	    {
		    $proplookup += [PSCustomObject]@{
			    ShortName = $lookup
			    DisplayName = $sourceserver.Configuration.$lookup.Displayname
		    }
	    }
		
	    foreach ($sourceprop in $sourceserver.Configuration.Properties)
	    {
		    $displayname = $sourceprop.DisplayName
		    $lookup = $proplookup | Where-Object { $_.DisplayName -eq $displayname }
			
		    if ($configs.length -gt 0 -and $configs -notcontains $lookup.ShortName) { continue }
			
		    $destprop = $destprops | Where-Object{ $_.Displayname -eq $displayname }
		    if ($destprop -eq $null)
		    {
			    Write-Warning "Configuration option '$displayname' does not exists on the destination instance."
			    continue
		    }
			
		    If ($Pscmdlet.ShouldProcess($destination, "Updating $displayname"))
		    {
			    try
			    {
				    $destOldPropValue = $destprop.configvalue
				    $destprop.configvalue = $sourceprop.configvalue
				    $destserver.ConnectionContext.ExecuteNonQuery("RECONFIGURE WITH OVERRIDE") | Out-Null
				    Write-Output "Updated $($destprop.displayname) from $destOldPropValue to $($sourceprop.configvalue)"
			    }
			    catch
			    {
				    Write-Error "Could not $($destprop.displayname) to $($sourceprop.configvalue). Feature may not be supported."
			    }
		    }
			
		    If ($Pscmdlet.ShouldProcess($destination, "Altering configuration"))
		    {
			    try
			    {
				    $destserver.Configuration.Alter()
			    }
			    catch
			    {
				    Write-Warning "Configuration option '$displayname' requires restart."
			    }
		    }
	    }
		
	    If ($Pscmdlet.ShouldProcess("both servers", "Updating sp_configure so that it does not show advanced options"))
	    {
		    $sourceserver.Configuration.ShowAdvancedOptions.ConfigValue = $false
		    $sourceserver.ConnectionContext.ExecuteNonQuery("RECONFIGURE WITH OVERRIDE") | Out-Null
		    $destserver.Configuration.ShowAdvancedOptions.ConfigValue = $false
		    $destserver.ConnectionContext.ExecuteNonQuery("RECONFIGURE WITH OVERRIDE") | Out-Null
	    }
    }
    END
    {
	    $sourceserver.ConnectionContext.Disconnect()
	    $destserver.ConnectionContext.Disconnect()
	
	    If ($Pscmdlet.ShouldProcess("console", "Showing finished message"))
	    {
		    Write-Output "Server configuration update finished"
	    }
    }
}