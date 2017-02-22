Function Find-DbaDependency
{
<#
.SYNOPSIS
Searches SQL Server to find user-owned objects (ie. not dbo or sa) or for any object owned by a specific user specified by the Pattern parameter.

.DESCRIPTION
Looks at the below list of objects to see if they are either owned by a user or a specific user (using the parameter -Pattern)
    Database Owner
    Agent Job Owner
    Used in Credential
    USed in Proxy
    SQL Agent Steps using a Proxy
    Endpoints
    Database Schemas
    Database Roles
    Dabtabase Assembles
    Database Synonyms

.PARAMETER SqlInstance
SqlInstance name or SMO object representing the SQL Server to connect to. This can be a collection and recieve pipeline input

.PARAMETER SqlCredential
PSCredential object to connect as. If not specified, current Windows login will be used.

.PARAMETER Pattern
The regex pattern that the command will search for

.NOTES 
Original Author: Stephen Bennett, https://sqlnotesfromtheunderground.wordpress.com/
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
Find-DbaDependency -SqlInstance sql2012 -Type Table -Name Northwind.dbo.Customers

Gets depenencies for the Customers table in the Northwind Database
#>
	[CmdletBinding(DefaultParameterSetName = "Default")]
	Param (
		[parameter(Position = 0, Mandatory = $true, ParameterSetName = "NotPiped")]
		[Alias("ServerInstance", "SqlServer", "SqlInstances")]
		[object[]]$SqlInstance,
		[System.Management.Automation.PSCredential]$SqlCredential,
		[parameter(Mandatory = $true, ParameterSetName = "NotPiped")]
		[ValidateSet('Table', 'Database', 'Whatever', 'NoIdea', 'MaybeThisIsntEvenRightPlzFigureOut')]
		[string]$Type = "Table",
		[parameter(Mandatory = $true, ParameterSetName = "NotPiped")]
		[string[]]$Name,
		# same goes for this

		[switch]$IncludeParent,
		[switch]$AllowSystemObjects,
		[parameter(ValueFromPipeline = $True, Mandatory = $true, ParameterSetName = "Piped")]
		[object[]]$SmoObject
	)
	begin
	{
		function Get-Dependency
		{
			# This probably can't reuse objects
			$scripter = New-Object Microsoft.SqlServer.Management.Smo.Scripter
			$options = New-Object Microsoft.SqlServer.Management.Smo.ScriptingOptions
			$options.DriAll = $true
			$options.AllowSystemObjects = $AllowSystemObjects
			$options.WithDependencies = $true
			$scripter.Options = $options
			$scripter.Server = $server
			
			# This has to be one by one in order to keep track of what you were originally searching for
			
			$urnCollection = New-Object Microsoft.SqlServer.Management.Smo.UrnCollection
			$urn = $object.urn
			$type = $object.urn.Type
			Write-Verbose "Adding $object which is a $type"
			$urnCollection.Add([Microsoft.SqlServer.Management.Sdk.Sfc.Urn]$object.urn)
			
			#now we set up an event listnenr go get progress reports
			$progressReportEventHandler = [Microsoft.SqlServer.Management.Smo.ProgressReportEventHandler] { $name = $_.Current.GetAttribute('Name'); Write-Verbose "Analysed $name" }
			$scripter.add_DiscoveryProgress($progressReportEventHandler)
			
			#create the dependency tree
			$dependencyTree = $scripter.DiscoverDependencies($urnCollection, $IncludeParent) #look for the parent objects for each object
			
			#and walk the dependencies to get the dependency tree.
			$dependencies = $scripter.WalkDependencies($dependencyTree)
			
			foreach ($dependency in $dependencies)
			{
				# This gets the full on SMO object that you can grab all the info from
				$richobject = $server.GetSmoObject($dependency.urn)
				
				[pscustomobject]@{
					ComputerName = $server.NetName
					SqlInstance = $server.ServiceName
					Parent = $object.Name
					ParentType = $object.Urn.Type # whatever
					Dependent = $richobject.Name
					Type = $dependency.Urn.Type
					Owner = $richobject.Owner # or whatever
					Urn = $richobject.Urn
					Object = $richobject
					# Script = $Object.Script() #mmm this may not work. Check to see if a Script() method exists first?
					# And so on
				} | Select-DefaultView -ExcludeProperty Urn, Object, Script
			}
		}
	}
	process
	{
		if ($SmoObject)
		{
			foreach ($object in $SmoObject)
			{
				# Find the parent to pass on to the function
				$parent = $object.parent
				do { $parent = $parent.parent }
				until ($parent.urn.type -eq "Server")
				$server = $parent
				
				# Do it!
				Get-Dependency $object
			}
			return
		}
		
		foreach ($Instance in $SqlInstance)
		{
			try
			{
				Write-Verbose "Connecting to $Instance"
				$server = Connect-SqlServer -SqlServer $Instance -SqlCredential $sqlcredential
			}
			catch
			{
				Write-Warning "Failed to connect to: $Instance"
				continue
			}
			
			if ($Type -eq "Table")
			{
				if ($Name -notmatch "^[\w\d\.-]+\.[\w\d\.-]+\.[\w\d\.-]+$")
				{
					Write-Warning "Tables must be fully qualified. Please pass name in the format of database.schema.table"
					continue
				}
				
				$database, $schema, $table = $Name.Split(".")
				
				try
				{
					$smotable = $server.Databases[$database].Tables | Where-Object { $_.Name -eq $table -and $_.Schema -eq $schema }
				}
				catch
				{
					# will catch below
				}
				
				if ($null -eq $smotable)
				{
					if ($null -eq $server.Databases[$database])
					{
						Write-Warning "Database ($database) does not exist"
					}
					else
					{
						Write-Warning "Table ($table) with schema owner $schema does not exist"
					}
					continue
				}
				
				Get-Dependency $smotable # check because it's returning the object as a dependent of itself
			}
		}
	}
}