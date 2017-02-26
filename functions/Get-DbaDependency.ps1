function Get-DbaDependency
{
    <#
       .SYNOPSIS
            Finds object dependencies and their relevant creation scripts.
        
        .DESCRIPTION
            This function recursively finds all objects that are dependent on the one passed to it.
            It will then retrieve rich information from them, including their creation scripts and the order in which it should be applied.
    
            By using the EnumParents switch, the function will instead retrieve all items the input depends upon (including their creation scripts).
    
            When retrieving everything that depends on the input, the lower the tier, the earlier it should be installed.
            When retrieving everything that the input depends upon however, the higher the tier, the earlier it should be installed.
        
            For more details on dependency, see:
            https://technet.microsoft.com/en-us/library/ms345449(v=sql.105).aspx
        
        .PARAMETER IncludeScript
            Setting this switch will cause the function to also retrieve the creation script of the dependency.
        
        .PARAMETER AllowSystemObjects
            Normally, system objects are ignored by this function as dependencies.
            This switch overrides that behavior.
        
        .PARAMETER EnumParents
            Causes the function to retrieve all objects the input depends upon, rather than retrieving everything that depends on the input.
        
        .PARAMETER Silent
            Replaces user friendly yellow warnings with bloody red exceptions of doom!
            Use this if you want the function to throw terminating errors you want to catch.
        
        .EXAMPLE
            $table = (Get-DbaDatabase -SqlInstance sql2012 Northwind).tables | Where Name -eq Customers
            $table | Get-DbaDependency
        
            Returns everything that depends on the "Customers" table
    
        .LINK
            https://dbatools.io/Get-DbaDependency
    #>
    [CmdletBinding()]
    Param (
        [Parameter(ValueFromPipeline = $true)]
        $InputObject,
        
        [switch]
        $AllowSystemObjects,
        
        [switch]
        $EnumParents,
        
        [switch]
        $Silent
    )
    
    Begin
    {
        #region Utility functions
        function Get-DependencyTree
        {
            [CmdletBinding()]
            Param (
                $Object,
                
                $Server,
                
                [bool]
                $AllowSystemObjects,
                
                [bool]
                $EnumParents,
                
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
            
            Write-Message -Silent $Silent -Level 5 -Message "Adding $Object which is a $($Object.urn.Type)" -FunctionName $FunctionName
            $urnCollection.Add([Microsoft.SqlServer.Management.Sdk.Sfc.Urn]$Object.urn)
            
            #now we set up an event listnenr go get progress reports
            $progressReportEventHandler = [Microsoft.SqlServer.Management.Smo.ProgressReportEventHandler] {
                $name = $_.Current.GetAttribute('Name');
                Write-Message -Silent $Silent -Level 5 -Message "Analysed $name" -FunctionName $FunctionName
            }
            $scripter.add_DiscoveryProgress($progressReportEventHandler)
            
            return $scripter.DiscoverDependencies($urnCollection, $EnumParents)
        }
        
        function Read-DependencyTree
        {
            [CmdletBinding()]
            Param (
                [System.Object]
                $InputObject,
                
                [int]
                $Tier,
                
                [System.Object]
                $Parent
            )
            
            Add-Member -InputObject $InputObject -Name Parent -Value $Parent -MemberType NoteProperty
            Add-Member -InputObject $InputObject -Name Tier -Value $Tier -MemberType NoteProperty -PassThru
            
            if ($InputObject.HasChildNodes) { Read-DependencyTree -InputObject $InputObject.FirstChild -Tier ($Tier + 1) -Parent $InputObject }
            if ($InputObject.NextSibling) { Read-DependencyTree -InputObject $InputObject.NextSibling -Tier $Tier -Parent $Parent }
        }
        
        function Get-DependencyTreeNodeDetail
        {
            [CmdletBinding()]
            Param (
                [Parameter(ValueFromPipeline = $true)]
                $SmoObject,
                
                $Server,
                
                $OriginalResource,
                
                [bool]
                $AllowSystemObjects
            )
            
            Begin
            {
                $scripter = New-Object Microsoft.SqlServer.Management.Smo.Scripter
                $options = New-Object Microsoft.SqlServer.Management.Smo.ScriptingOptions
                $options.DriAll = $true
                $options.AllowSystemObjects = $AllowSystemObjects
                $options.WithDependencies = $true
                $scripter.Options = $options
                $scripter.Server = $Server
            }
            
            process
            {
                foreach ($Item in $SmoObject)
                {
                    $richobject = $Server.GetSmoObject($Item.urn)
                    $parent = $Server.GetSmoObject($Item.Parent.Urn)
                    
                    $NewObject = [pscustomobject]@{
                        ComputerName = $server.NetName
                        InstanceName = $server.ServiceName
                        SqlInstance = $server.DomainInstanceName
                        Parent = $parent.Name
                        ParentType = $parent.Urn.Type
                        Dependent = $richobject.Name
                        IsSchemaBound = $Item.IsSchemaBound
                        Type = $Item.Urn.Type
                        Owner = $richobject.Owner
                        Urn = $richobject.Urn
                        Object = $richobject
                        Tier = $Item.Tier
                        Script = ""
                        OriginalResource = $OriginalResource
                    }
                    
                    $SQLscript = $scripter.EnumScriptWithList($richobject)
                    
                    # I can't remember how to remove these options and their syntax is breaking stuff
                    $SQLscript = $SQLscript -replace "SET ANSI_NULLS ON", ""
                    $SQLscript = $SQLscript -replace "SET QUOTED_IDENTIFIER ON", ""
                    $NewObject.script = "$SQLscript go"
                    
                    $NewObject
                }
            }
        }
        #endregion Utility functions
    }
    Process
    {
        foreach ($Item in $InputObject)
        {
            Write-Message -Silent $Silent -Level 5 -Message "Processing: $Item"
            if ($null -eq $Item.urn)
            {
                Stop-Function -Message "$Item is not a valid SMO object" -Silent $Silent -Category InvalidData -Continue -Target $Item
            }
            
            # Find the server object to pass on to the function
            $parent = $Item.parent
            
            do { $parent = $parent.parent }
            until (($parent.urn.type -eq "Server") -or (-not $parent))
            
            if (-not $parent)
            {
                Stop-Function -Message "Failed to find valid server object in input: $Item" -Silent $Silent -Category InvalidData -Continue -Target $Item
            }
            
            $server = $parent
            
            $tree = Get-DependencyTree -Object $Item -AllowSystemObjects $false -Server $server -FunctionName (Get-PSCallStack)[0].COmmand -Silent $Silent -EnumParents $EnumParents
            if ($tree.Count -lt 2)
            {
                Write-Message -Message "No dependencies detected for $($Item)" -Level 2 -Silent $Silent
                continue
            }
            $resolved = Read-DependencyTree -InputObject $tree.FirstChild.FirstChild -Tier 0 -Parent $tree.FirstChild
            $resolved | Get-DependencyTreeNodeDetail -Server $server -OriginalResource $Item -AllowSystemObjects $AllowSystemObjects | Sort-Object -Property Tier
        }
    }
}
