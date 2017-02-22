Function Find-DbaDependency
{
<#
    .SYNOPSIS
        Finds object dependencies and their relevant creation scripts.
    
    .DESCRIPTION
        Finds object dependencies and their relevant creation scripts.
    
    .PARAMETER InputObject
        The object(s), the dependencies of which should be retrieved.
    
    .PARAMETER IncludeScript
        Setting this switch will cause the function to also retrieve the creation script of the dependency.
    
    .PARAMETER AllowSystemObjects
        Normally, system objects are ignored by this function as dependencies.
        This switch overrides that behavior.
    
    .PARAMETER Silent
        Replaces user friendly yellow warnings with bloody red exceptions of doom!
        Use this if you want the function to throw terminating errors you want to catch.
    
    .EXAMPLE
        $table = (Get-DbaDatabase -SqlInstance sql2012 Northwind).tables | Where Name -eq Customers
        $table | Find-DbaDependency
    
        Returns all dependencies of the "Customers" table
    
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
#>
    [CmdletBinding()]
    Param (
        [parameter(ValueFromPipeline = $True, Mandatory = $true)]
        [object[]]
        $InputObject,
        
        [switch]
        $IncludeScript,
        
        [switch]
        $AllowSystemObjects,
        
        [switch]
        $Silent
    )
    begin
    {
        $FunctionName = (Get-PSCallStack)[0].Command
        
        # This is a fucntion that runs recursively against rich SMO objects
        function Get-Dependency
        {
            [CmdletBinding()]
            Param (
                $Object,
                
                $Server,
                
                [string[]]
                $UrnDuplicate,
                
                [bool]
                $IncludeScript,
                
                [bool]
                $AllowSystemObjects,
                
                $OriginalResource,
                
                [string]
                $FunctionName,
                
                [bool]
                $Silent
            )
            
            $scripter = New-Object Microsoft.SqlServer.Management.Smo.Scripter
            $options = New-Object Microsoft.SqlServer.Management.Smo.ScriptingOptions
            $options.DriAll = $true
            $options.AllowSystemObjects = $AllowSystemObjects
            $options.WithDependencies = $true
            $scripter.Options = $options
            $scripter.Server = $Server
            
            $urnCollection = New-Object Microsoft.SqlServer.Management.Smo.UrnCollection
            $urn = $object.urn
            
            Write-Message -Silent $Silent -Level 5 -Message "Adding $object which is a $($object.urn.Type)" -FunctionName $FunctionName
            $urnCollection.Add([Microsoft.SqlServer.Management.Sdk.Sfc.Urn]$object.urn)
            
            #now we set up an event listnenr go get progress reports
            $progressReportEventHandler = [Microsoft.SqlServer.Management.Smo.ProgressReportEventHandler] {
                $name = $_.Current.GetAttribute('Name');
                Write-Message -Silent $Silent -Level 5 -Message "Analysed $name" -FunctionName $FunctionName
            }
            $scripter.add_DiscoveryProgress($progressReportEventHandler)
            
            $dependencyTree = $scripter.DiscoverDependencies($urnCollection, $IncludeParent) #look for the parent objects for each object
            $dependencies = $scripter.WalkDependencies($dependencyTree)
            
            foreach ($dependency in $dependencies)
            {
                
                # This checks to see if it's already been done because of recursion
                $urnstring = $dependency.urn.toString()
                
                if ($urnstring -notin $UrnDuplicate)
                {
                    Write-Message -Silent $Silent -Level 9 -Message "not a dupe" -FunctionName $FunctionName
                    $UrnDuplicate += $urnstring
                }
                else
                {
                    Write-Message -Silent $Silent -Level 9 -Message "caught a dupe $urnstring" -FunctionName $FunctionName
                    continue
                }
                
                # This gets the full on SMO object that you can grab all the info from
                $richobject = $server.GetSmoObject($dependency.urn)
                
                $NewObject = [pscustomobject]@{
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
                    Script = ""
                    OriginalResource = $OriginalResource
                }
                
                if ($IncludeScript)
                {
                    $SQLscript = $scripter.EnumScriptWithList($richobject)
                    
                    # I can't remember how to remove these options and their syntax is breaking stuff
                    $SQLscript = $SQLscript -replace "SET ANSI_NULLS ON", ""
                    $SQLscript = $SQLscript -replace "SET QUOTED_IDENTIFIER ON", ""
                    $NewObject.script = "$SQLscript go"
                }
                
                $NewObject #| Select-DefaultView -ExcludeProperty Urn, Object
                
                # This is recursion
                $splat = @{
                    Object = $richobject
                    Server = $Server
                    UrnDuplicate = $UrnDuplicate
                    IncludeScript = $IncludeScript
                    AllowSystemObjects = $AllowSystemObjects
                    OriginalResource = $OriginalResource
                    FunctionName = $FunctionName
                    Silent = $Silent
                }
                Get-Dependency @splat
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
                Write-Message -Silent $Silent -Level 5 -Message "Processing: $Object"
                if ($null -eq $object.urn)
                {
                    Stop-Function -Message "$object is not a valid SMO object" -Silent $Silent -Category InvalidData -Continue -Target $object
                }
                
                # Find the server object to pass on to the function
                $parent = $object.parent
                
                do { $parent = $parent.parent }
                until (($parent.urn.type -eq "Server") -or (-not $parent))
                
                if (-not $parent)
                {
                    Stop-Function -Message "Failed to find valid server object in input: $object" -Silent $Silent -Category InvalidData -Continue -Target $object
                }
                
                $server = $parent
                
                $splat = @{
                    Object = $object
                    Server = $Server
                    UrnDuplicate = @()
                    IncludeScript = $IncludeScript
                    AllowSystemObjects = $AllowSystemObjects
                    OriginalResource = $object
                    FunctionName = $FunctionName
                    Silent = $Silent
                }
                Get-Dependency @splat
            }
            return
        }
    }
}
