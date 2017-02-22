Function Find-DbaDependency
{
<#
.SYNOPSIS
Finds and scripts object dependencies

.DESCRIPTION
Finds and scripts object dependencies

.PARAMETER InputObject
The regex pattern that the command will search for
	
.PARAMETER IncludeParent
The regex pattern that the command will search for

.PARAMETER IncludeScript
The regex pattern that the command will search for
	
.PARAMETER AllowSystemObjects
The regex pattern that the command will search for
	
.NOTES 
dbatools PowerShell module (https://dbatools.io, clemaire@gmail.com)
Copyright (C) 2016 Chrissy LeMaire
This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
You should have received a copy of the GNU General Public License along with this program.  If not, see <http://www.gnu.org/licenses/>.
You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.	

.LINK
https://dbatools.io/Find-DbaDependency
	
.EXAMPLE
$table = (Get-DbaDatabase -SqlInstance sql2012 Northwind).tables | Where Name -eq Customers
$table | Find-DbaDependency

#>
	[CmdletBinding()]
	Param (
		[parameter(ValueFromPipeline = $True, Mandatory = $true)]
		[object[]]$InputObject,
		[switch]$IncludeParent,
		[switch]$IncludeScript,
		[switch]$AllowSystemObjects
	)
	begin
	{
		# This is a fucntion that runs recursively against rich SMO objects
		function Get-Dependency ($object)
		{
			$scripter = New-Object Microsoft.SqlServer.Management.Smo.Scripter
			$options = New-Object Microsoft.SqlServer.Management.Smo.ScriptingOptions
			$options.DriAll = $true
			$options.AllowSystemObjects = $AllowSystemObjects
			$options.WithDependencies = $true
			$scripter.Options = $options
			$scripter.Server = $server
			
			$urnCollection = New-Object Microsoft.SqlServer.Management.Smo.UrnCollection
			$urn = $object.urn
			$type = $object.urn.Type
						
			Write-Verbose "Adding $object which is a $type"
			$urnCollection.Add([Microsoft.SqlServer.Management.Sdk.Sfc.Urn]$object.urn)
			
			#now we set up an event listnenr go get progress reports
			$progressReportEventHandler = [Microsoft.SqlServer.Management.Smo.ProgressReportEventHandler] { $name = $_.Current.GetAttribute('Name'); Write-Verbose "Analysed $name" }
			$scripter.add_DiscoveryProgress($progressReportEventHandler)
			
			$dependencyTree = $scripter.DiscoverDependencies($urnCollection, $IncludeParent) #look for the parent objects for each object
			$dependencies = $scripter.WalkDependencies($dependencyTree)
			
			foreach ($dependency in $dependencies)
			{
				
				# This checks to see if it's already been done because of recursion
				$urnstring = $dependency.urn.toString()
				
				if ($urnstring -notin $urndupes)
				{
					Write-Warning "not a dupe"
					$urndupes += $urnstring
				}
				else
				{
					Write-Warning "caught a dupe $urnstring"
					continue
				}
				
				# This gets the full on SMO object that you can grab all the info from
				$richobject = $server.GetSmoObject($dependency.urn)

				$object = [pscustomobject]@{
					ComputerName = $server.NetName
					InstanceName = $server.ServiceName
					SqlInstance = $server.DomainInstanceName
					Parent = $object.Name
					ParentType = $object.Urn.Type
					Dependent = $richobject.Name
					Type = $dependency.Urn.Type
					Owner = $richobject.Owner
					Urn = $richobject.Urn
					Object = $richobject
				}
				
				if ($includeScript)
				{
					$script = $scripter.EnumScriptWithList($richobject)
					
					# I can't remember how to remove these options and their syntax is breaking stuff
					$script = $script -replace "SET ANSI_NULLS ON", ""
					$script = $script -replace "SET QUOTED_IDENTIFIER ON", ""
					$script = "$script go"
					Add-Member -InputObject $object -MemberType NoteProperty -Name Script -Value $script
				}
				
				$object | Select-DefaultView -ExcludeProperty Urn, Object
				
				# This is recursion
				Get-Dependency $richobject
			}
		}
	}
	process
	{
		# This should be helpful for recursion?
		$urndupes = @()
		if ($InputObject)
		{
			foreach ($object in $InputObject)
			{
				if ($null -eq $object.urn)
				{
					Write-Warning "$object is not a valid SMO object"
					continue
				}
				
				# Find the server object to pass on to the function
				$parent = $object.parent
				
				do { $parent = $parent.parent }
				until ($parent.urn.type -eq "Server")
				
				$server = $parent
				
				if ($includeparent)
				{
					Get-Dependency $object
				}
				
				Get-Dependency $object
			}
			return
		}
	}
}