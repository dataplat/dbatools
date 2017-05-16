function Copy-DbaAgentCategory
{
<#
.SYNOPSIS 
Copy-DbaAgentCategory migrates SQL Agent categories from one SQL Server to another. This is similar to sp_add_category.

https://msdn.microsoft.com/en-us/library/ms181597.aspx

.DESCRIPTION
By default, all SQL Agent categories for Jobs, Operators and Alerts are copied. 

The -OperatorCategories parameter is autopopulated for command-line completion and can be used to copy only specific operator categories.
The -AgentCategories parameter is autopopulated for command-line completion and can be used to copy only specific agent categories.
The -JobCategories parameter is autopopulated for command-line completion and can be used to copy only specific job categories.

If the category already exists on the destination, it will be skipped unless -Force is used.  

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

.PARAMETER CategoryType
Specifies the Category Type to migrate. Valid options are Job, Alert and Operator. When CategoryType is specified, all categories from the selected type will be migrated. For granular migrations, use the three parameters below.

.PARAMETER OperatorCategories 
This parameter is autopopulated for command-line completion and can be used to copy only specific operator categories.

.PARAMETER AgentCategories
This parameter is autopopulated for command-line completion and can be used to copy only specific agent categories.

.PARAMETER JobCategories
This parameter is autopopulated for command-line completion and can be used to copy only specific job categories.

.PARAMETER WhatIf 
Shows what would happen if the command were to run. No actions are actually performed. 

.PARAMETER Confirm 
Prompts you for confirmation before executing any changing operations within the command. 

.PARAMETER Force
Drops and recreates the XXXXX if it exists

.NOTES
Tags: Migration, Agent
Author: Chrissy LeMaire (@cl), netnerds.net
Requires: sysadmin access on SQL Servers

dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.

You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.

.LINK
https://dbatools.io/Copy-DbaAgentCategory

.EXAMPLE   
Copy-DbaAgentCategory -Source sqlserver2014a -Destination sqlcluster

Copies all operator categories from sqlserver2014a to sqlcluster, using Windows credentials. If operator categories with the same name exist on sqlcluster, they will be skipped.

.EXAMPLE   
Copy-DbaAgentCategory -Source sqlserver2014a -Destination sqlcluster -OperatorCategory PSOperator -SourceSqlCredential $cred -Force

Copies a single operator category, the PSOperator operator category from sqlserver2014a to sqlcluster, using SQL credentials for sqlserver2014a and Windows credentials for sqlcluster. If a operator category with the same name exists on sqlcluster, it will be dropped and recreated because -Force was used.

.EXAMPLE   
Copy-DbaAgentCategory -Source sqlserver2014a -Destination sqlcluster -WhatIf -Force

Shows what would happen if the command were executed using force.
#>
	[CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
	param (
		[parameter(Mandatory = $true)]
		[object]$Source,
		[parameter(Mandatory = $true)]
		[object]$Destination,
		[Parameter(ParameterSetName = 'SpecifcAlerts')]
		[ValidateSet('Job', 'Alert', 'Operator')]
		[string[]]$CategoryType,
		[System.Management.Automation.PSCredential]$SourceSqlCredential,
		[System.Management.Automation.PSCredential]$DestinationSqlCredential,
		[switch]$Force
	)
	DynamicParam { if ($source) { return (Get-ParamSqlAgentCategories -SqlServer $Source -SqlCredential $SourceSqlCredential) } }
	
	BEGIN
	{
		
		Function Copy-JobCategory
		{
			<#
			.SYNOPSIS 
			Copy-JobCategory migrates job categories from one SQL Server to another. 

			.DESCRIPTION
			By default, all job categories are copied. The -JobCategories parameter is autopopulated for command-line completion and can be used to copy only specific job categories.

			If the associated credential for the category does not exist on the destination, it will be skipped. If the job category already exists on the destination, it will be skipped unless -Force is used.  
			#>
			param (
				[string[]]$JobCategories
			)
			
			PROCESS
			{
				
				$serverjobcategories = $sourceserver.JobServer.JobCategories | Where-Object { $_.ID -ge 100 }
				$destjobcategories = $destserver.JobServer.JobCategories | Where-Object { $_.ID -ge 100 }
				
				foreach ($jobcategory in $serverjobcategories)
				{
					$categoryname = $jobcategory.name
					if ($jobcategories.count -gt 0 -and $jobcategories -notcontains $categoryname) { continue }
					
					if ($destjobcategories.name -contains $jobcategory.name)
					{
						if ($force -eq $false)
						{
							Write-Warning "Job category $categoryname exists at destination. Use -Force to drop and migrate."
							continue
						}
						else
						{
							If ($Pscmdlet.ShouldProcess($destination, "Dropping job category $categoryname and recreating"))
							{
								try
								{
									Write-Verbose "Dropping Job category $categoryname"
									$destserver.jobserver.jobcategories[$categoryname].Drop()
									
								}
								catch { 
									Write-Exception $_ 
									continue
								}
							}
						}
					}
					
				If ($Pscmdlet.ShouldProcess($destination, "Creating Job category $categoryname"))
					{
						try
						{
							Write-Output "Copying Job category $categoryname"
							$sql = $jobcategory.Script() | Out-String
							$sql = $sql -replace [Regex]::Escape("'$source'"), [Regex]::Escape("'$destination'")
							Write-Verbose $sql
							$destserver.ConnectionContext.ExecuteNonQuery($sql) | Out-Null
						}
						catch
						{
							Write-Exception $_
						}
					}
				}
			}
			
			END
			{
				If ($Pscmdlet.ShouldProcess("console", "Showing finished message")) { Write-Output "Job category migration finished" }
			}
		}
		
		Function Copy-OperatorCategory
		{
			<#
			.SYNOPSIS 
			Copy-OperatorCategory migrates operator categories from one SQL Server to another. 

			.DESCRIPTION
			By default, all operator categories are copied. The -OperatorCategories parameter is autopopulated for command-line completion and can be used to copy only specific operator categories.

			If the associated credential for the category does not exist on the destination, it will be skipped. If the operator category already exists on the destination, it will be skipped unless -Force is used.  
			#>
			[CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
			param (
				[string[]]$OperatorCategories
			)
			
			PROCESS
			{
				$serveroperatorcategories = $sourceserver.JobServer.OperatorCategories | Where-Object { $_.ID -ge 100 }
				$destoperatorcategories = $destserver.JobServer.OperatorCategories | Where-Object { $_.ID -ge 100 }
				
				foreach ($operatorcategory in $serveroperatorcategories)
				{
					$categoryname = $operatorcategory.name
				
					if ($operatorcategories.count -gt 0 -and $operatorcategories -notcontains $categoryname) { continue }
					
					if ($destoperatorcategories.name -contains $operatorcategory.name)
					{
						if ($force -eq $false)
						{
							Write-Warning "Operator category $categoryname exists at destination. Use -Force to drop and migrate."
							continue
						}
						else
						{
							If ($Pscmdlet.ShouldProcess($destination, "Dropping operator category $categoryname and recreating"))
							{
								try
								{
									Write-Verbose "Dropping Operator category $categoryname"
									$destserver.jobserver.operatorcategories[$categoryname].Drop()
									Write-Output "Copying Operator category $categoryname"
									$sql = $operatorcategory.Script() | Out-String
									$sql = $sql -replace [Regex]::Escape("'$source'"), [Regex]::Escape("'$destination'")
									Write-Verbose $sql
									$destserver.ConnectionContext.ExecuteNonQuery($sql) | Out-Null
								}
								catch { Write-Exception $_ }
							}
						}
					}
					else
					{
						If ($Pscmdlet.ShouldProcess($destination, "Creating Operator category $categoryname"))
						{
							try
							{
								Write-Output "Copying Operator category $categoryname"
								$sql = $operatorcategory.Script() | Out-String
								$sql = $sql -replace [Regex]::Escape("'$source'"), [Regex]::Escape("'$destination'")
								Write-Verbose $sql
								$destserver.ConnectionContext.ExecuteNonQuery($sql) | Out-Null
							}
							catch
							{
								Write-Exception $_
							}
						}
					}
				}
			}
			
			END
			{
				If ($Pscmdlet.ShouldProcess("console", "Showing finished message")) { Write-Output "Operator category migration finished" }
			}
		}
		
		Function Copy-AlertCategory
		{
			<#
			.SYNOPSIS 
			Copy-AlertCategory migrates alert categories from one SQL Server to another. 

			.DESCRIPTION
			By default, all alert categories are copied. The -AlertCategories parameter is autopopulated for command-line completion and can be used to copy only specific alert categories.

			If the associated credential for the category does not exist on the destination, it will be skipped. If the alert category already exists on the destination, it will be skipped unless -Force is used.  
			
			#>
			[CmdletBinding(DefaultParameterSetName = "Default", SupportsShouldProcess = $true)]
			param (
				[string[]]$AlertCategories
			)
			
			PROCESS
			{
				if ($sourceserver.versionMajor -lt 9 -or $destserver.versionMajor -lt 9)
				{
					throw "Server AlertCategories are only supported in SQL Server 2005 and above. Quitting."
				}
				
				$serveralertcategories = $sourceserver.JobServer.AlertCategories | Where-Object { $_.ID -ge 100 }
				$destalertcategories = $destserver.JobServer.AlertCategories | Where-Object { $_.ID -ge 100 }
				
				foreach ($alertcategory in $serveralertcategories)
				{
					$categoryname = $alertcategory.name
					if ($alertcategories.length -gt 0 -and $alertcategories -notcontains $categoryname) { continue }
					
					if ($destalertcategories.name -contains $alertcategory.name)
					{
						if ($force -eq $false)
						{
							Write-Warning "Alert category $categoryname exists at destination. Use -Force to drop and migrate."
							continue
						}
						else
						{
							If ($Pscmdlet.ShouldProcess($destination, "Dropping alert category $categoryname and recreating"))
							{
								try
								{
									Write-Verbose "Dropping Alert category $categoryname"
									$destserver.jobserver.alertcategories[$categoryname].Drop()
									Write-Output "Copying Alert category $categoryname"
									$sql = $alertcategory.Script() | Out-String
									$sql = $sql -replace [Regex]::Escape("'$source'"), [Regex]::Escape("'$destination'")
									Write-Verbose $sql
									$destserver.ConnectionContext.ExecuteNonQuery($sql) | Out-Null
								}
								catch { Write-Exception $_ }
							}
						}
					}
					else
					{
						If ($Pscmdlet.ShouldProcess($destination, "Creating Alert category $categoryname"))
						{
							try
							{
								Write-Output "Copying Alert category $categoryname"
								$sql = $alertcategory.Script() | Out-String
								$sql = $sql -replace [Regex]::Escape("'$source'"), [Regex]::Escape("'$destination'")
								Write-Verbose $sql
								$destserver.ConnectionContext.ExecuteNonQuery($sql) | Out-Null
							}
							catch
							{
								Write-Exception $_
							}
						}
					}
				}
			}
			
			END
			{
				If ($Pscmdlet.ShouldProcess("console", "Showing finished message")) { Write-Output "Alert category migration finished" }
			}
		}
		
		$operatorcategories = $psboundparameters.OperatorCategories
		$alertcategories = $psboundparameters.AlertCategories
		$jobcategories = $psboundparameters.JobCategories
		
		$sourceserver = Connect-SqlServer -SqlServer $Source -SqlCredential $SourceSqlCredential
		$destserver = Connect-SqlServer -SqlServer $Destination -SqlCredential $DestinationSqlCredential
		
		$source = $sourceserver.DomainInstanceName
		$destination = $destserver.DomainInstanceName
		
	}
	
	PROCESS
	{
		if ($CategoryType.count -gt 0)
		{
			
			switch ($CategoryType)
			{
				"Job" {
					Copy-JobCategory
				}
				
				"Alert" {
					Copy-AlertCategory
				}
				
				"Operator" {
					Copy-OperatorCategory
				}
			}
			
			return
		}
		
		if (($operatorcategories.count + $alertcategories.count + $jobcategories.count) -gt 0)
		{
			
			if ($operatorcategories.count -gt 0)
			{
				Copy-OperatorCategory -OperatorCategories $operatorcategories 
			}
			
			if ($alertcategories.count -gt 0)
			{
				Copy-AlertCategory -AlertCategories $alertcategories 
			}
			
			if ($jobcategories.count -gt 0)
			{
				Copy-JobCategory -JobCategories $jobcategories 
			}
			
			return
		}
		
		Copy-OperatorCategory 
		Copy-AlertCategory 
		Copy-JobCategory 
	}
	
	END
	{
		
		$sourceserver.ConnectionContext.Disconnect()
		$destserver.ConnectionContext.Disconnect()
		
        If ($Pscmdlet.ShouldProcess("console", "Showing finished message")) { Write-Output "Agent category migration finished" }
        Test-DbaDeprecation -DeprecatedOn "1.0.0" -Silent:$false -Alias Copy-SqlAgentCategory
	}
}
