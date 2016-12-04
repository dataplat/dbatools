Function Copy-SqlMaintenancePlan
{
<#
.SYNOPSIS 
Copy-SqlMaintenancePlan migrates Maintenance Plans from one SQL Server to another. This is used in conjunction with Copy-SqlJob.

https://msdn.microsoft.com/en-us/library/ms187658.aspx

.DESCRIPTION
By default, all maintenance plans found in msdb.sysssispackages table. This DOES NOT copy the associated SQL Agent Job.

If the maintenance plan already exist on the destination, it will be skipped unless -Force is used.

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

.PARAMETER Force
Drops and recreates the maintenance plan if it exist.

.NOTES 
Author: Shawn Melton (@wsmelton)
Requires: sysadmin access on SQL Servers

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Copy-SqlMaintenancePlan

.EXAMPLE
Copy-SqlMaintenancePlan -Source sqlserver2014a -Destination sqlcluster
Copies all maintenance plans from sqlserver2014a to sqlcluster, using Windows credentials. If maintenance plans exist with the same name on sqlcluster, they will be skipped.

.EXAMPLE   
Copy-SqlMaintenancePlan -Source sqlserver2014a -Destination sqlcluster -Plan MyBackup -SqlCredential $cred -Force

Copies a single maintenance plan, the MyBackup, from sqlserver2014a to sqlcluster, using SQL credentials for sqlserver2014a and Windows credentials for sqlcluster. If a plan with the same name exist on sqlcluster, it will be removed and recreated because -Force was used.

.EXAMPLE   
Copy-SqlMaintenancePlan -Source sqlserver2014a -Destination sqlcluster -WhatIf -Force

Shows what would happen if the command were executed using -Force.
#>
	[CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
	Param (
		[parameter(Mandatory = $true)]
		[object]$Source,
		[parameter(Mandatory = $true)]
		[object]$Destination,
		[System.Management.Automation.PSCredential]$SourceSqlCredential,
		[System.Management.Automation.PSCredential]$DestinationSqlCredential,
		[switch]$Force
	)	
	DynamicParam { if ($source) { return (Get-ParamSqlMaintenancePlans -SqlServer $source -SqlCredential $SourceSqlCredential) } }
	
	BEGIN
	{
		$plans = $psboundparameters.MaintenancePlans
		$exclude = $psboundparameters.Exclude

		$sourceserver = Connect-SqlServer -SqlServer $Source -SqlCredential $SourceSqlCredential
		$destserver = Connect-SqlServer -SqlServer $Destination -SqlCredential $DestinationSqlCredential

		$source = $sourceserver.DomainInstanceName
		$destination = $destserver.DomainInstanceName
	}
	
	PROCESS
	{
		$sql = "SELECT plans.[name] AS plan_name, plans.id AS plan_id
			FROM msdb.dbo.sysmaintplan_plans AS plans"

		$sourceMaintPlanList = $sourceserver.ConnectionContext.ExecuteWithResults($sql).Tables.Rows
		$destMaintPlanList = $destserver.ConnectionContext.ExecuteWithResults($sql).Tables.Rows

		foreach ($plan in $sourceMaintPlanList)
		{
			$planname = $plan.plan_name
			$planid = $plan.plan_id

			if ($plans.count -gt 0 -and $plans -notcontains $planname -or $exclude -contains $planname)
			{ continue }

			if ($destMaintPlanList.plan_name -contains $plans)
			{
				if ($force -eq $false)
				{
					Write-Warning "[Plan: $planname] exist at destination. Use -Force to drop and migrate."
					continue
				}
				else
				{
					if ($Pscmdlet.ShouldProcess($destination, "Dropping Maintenance Plan: $planname on target $destination"))
					{
					#folderid (08AA12D5-8F98-4DAB-A4FC-980B150A5DC8) = Maintenance Plans folder under MSDB
						#
						$sql = "
						EXECUTE msdb.dbo.sp_maintplan_delete_plan 
							@plan_id=N'{$planid}' 
						EXECUTE [msdb].[dbo].[sp_ssis_deletepackage] 
							@name = N'$planname', 
							@folderid = '08AA12D5-8F98-4DAB-A4FC-980B150A5DC8'
						"
						try
						{
							Write-Output "Dropping Maintenance Plan $planname on $destination"
							$destserver.ConnectionContext.ExecuteNonQuery($sql) > $null
						}
						catch
						{
							Write-Exception $_
							continue
						}
					}
				}
			}
			if ($Pscmdlet.ShouldProcess($destination, "Creating Maintenance Plan: $planname"))
			{
				try
				{
					Write-Output "Copying Maintenance Plan $planname"
					$sql = "
					SELECT [name], [id], [description], [createdate], [folderid], [ownersid],
					CAST(
					   CAST(
						  REPLACE(
							 CAST(
								CAST(packagedata AS varbinary(max)
								) AS varchar(max)
							 ),
							 '$source','$destination')
					   AS xml)
					AS varbinary(max) ) AS packagedata,
					packageformat, packagetype, vermajor, verminor, verbuild, vercomments, verid, isencrypted, readrolesid, writerolesid
					FROM [msdb].[dbo].[sysssispackages]
					WHERE name = '$planname'"

					Write-Verbose "[SELECT] query - Maintenance metadata"
					Write-Verbose $sql
					$MaintMetaData = $sourceserver.ConnectionContext.ExecuteWithResults($sql).Tables.Rows

					$sql = "INSERT INTO [msdb].[dbo].[sysssispackages] (
						[name],[id],[description],[createdate],[folderid],[ownersid],[packagedata],[packageformat],[packagetype],[vermajor]
						,[verminor],[verbuild],[vercomments],[verid],[isencrypted],[readrolesid],[writerolesid])
						VALUES (@name,@id,@description,@createdate,
								@folderid,@ownersid,
								@packagedata,@packageformat,@packagetype,
								@vermajor,@verminor,@verbuild,@vercomments,@verid,
								@isencrypted,@readrolesid,@writerolesid)"
					$cn = New-Object System.Data.SqlClient.SqlConnection
					$cn.ConnectionString = $destserver.ConnectionContext.ConnectionString
					$cmd = New-Object System.Data.SqlClient.SqlCommand($sql,$cn)
					$cn.Open()

					#region Adding parameters
					$cmd.Parameters.Add("@name",[System.Data.SqlDbType]"VarChar",128) > $null
					$cmd.Parameters.Add("@id",[System.Data.SqlDbType]"UniqueIdentifier") > $null
					$cmd.Parameters.Add("@description",[System.Data.SqlDbType]"NVarChar",2048) > $null
					$cmd.Parameters.Add("@createdate",[System.Data.SqlDbType]"DateTime") > $null
					$cmd.Parameters.Add("@folderid",[System.Data.SqlDbType]"UniqueIdentifier") > $null
					$cmd.Parameters.Add("@ownersid",[System.Data.SqlDbType]"VarBinary",85) > $null
					$cmd.Parameters.Add("@packagedata",[System.Data.SqlDbType]"Image") > $null
					$cmd.Parameters.Add("@packageformat",[System.Data.SqlDbType]"Int") > $null
					$cmd.Parameters.Add("@packagetype",[System.Data.SqlDbType]"Int") > $null
					$cmd.Parameters.Add("@vermajor",[System.Data.SqlDbType]"Int") > $null
					$cmd.Parameters.Add("@verminor",[System.Data.SqlDbType]"Int") > $null
					$cmd.Parameters.Add("@verbuild",[System.Data.SqlDbType]"Int") > $null
					$cmd.Parameters.Add("@vercomments",[System.Data.SqlDbType]"NVarChar",2048) > $null
					$cmd.Parameters.Add("@verid",[System.Data.SqlDbType]"UniqueIdentifier") > $null
					$cmd.Parameters.Add("@isencrypted",[System.Data.SqlDbType]"Bit") > $null
					$cmd.Parameters.Add("readrolesid",[System.Data.SqlDbType]"VarBinary",85) > $null
					$cmd.Parameters.Add("writerolesid",[System.Data.SqlDbType]"VarBinary",85) > $null
					#endregion Adding parameters
					#region Set parameter values
					$cmd.Parameters["@name"].Value = $MaintMetaData.name
					$cmd.Parameters["@id"].Value = $MaintMetaData.id
					$cmd.Parameters["@description"].Value = $MaintMetaData.description
					$cmd.Parameters["@createdate"].Value = $MaintMetaData.createdate
					$cmd.Parameters["@folderid"].Value = $MaintMetaData.folderid
					$cmd.Parameters["@ownersid"].Value = $MaintMetaData.ownersid
					$cmd.Parameters["@packagedata"].Value = $MaintMetaData.packagedata
					$cmd.Parameters["@packageformat"].Value = $MaintMetaData.packageformat
					$cmd.Parameters["@packagetype"].Value = $MaintMetaData.packagetype
					$cmd.Parameters["@vermajor"].Value = $MaintMetaData.vermajor
					$cmd.Parameters["@verminor"].Value = $MaintMetaData.verminor
					$cmd.Parameters["@verbuild"].Value = $MaintMetaData.verbuild
					$cmd.Parameters["@vercomments"].Value = $MaintMetaData.vercomments
					$cmd.Parameters["@verid"].Value = $MaintMetaData.verid
					$cmd.Parameters["@isencrypted"].Value = $MaintMetaData.isencrypted
					$cmd.Parameters["readrolesid"].Value = $MaintMetaData.readrolesid
					$cmd.Parameters["writerolesid"].Value = $MaintMetaData.writerolesid
					#endregion Set parameter values

					$cmd.ExecuteNonQuery() > $null
					$cn.Close()
				}
				catch
				{
					Write-Exception $_
					continue
				}
			}
		}
	}
	END
	{
			$sourceserver.ConnectionContext.Disconnect()
			$destserver.ConnectionContext.Disconnect()
			If ($Pscmdlet.ShouldProcess("console", "Showing final message"))
			{
				Write-Output "Maintenance Plan migration finished"
			}
	}
}