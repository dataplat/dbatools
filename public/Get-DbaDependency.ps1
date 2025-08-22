function Get-DbaDependency {
    <#
    .SYNOPSIS
        Maps SQL Server object dependencies and generates creation scripts in proper deployment order

    .DESCRIPTION
        This function discovers SQL Server object dependencies using SMO (SQL Server Management Objects) and returns detailed information including creation scripts and deployment order. 
        By default, it finds all objects that depend on your input object - perfect for impact analysis before making changes or understanding what might break if you modify something.
        
        The function returns objects in hierarchical tiers, showing you exactly which objects need to be created first when deploying to a new environment.
        Each result includes the T-SQL creation script, so you can generate deployment scripts in the correct dependency order without manually figuring out prerequisites.

        Use the 'Parents' switch to reverse the direction and find what your object depends on instead - useful for understanding all the prerequisites needed before creating or moving an object.
        This is particularly valuable when migrating individual objects between environments or troubleshooting missing dependencies.

        For more details on dependency relationships, see:
        https://technet.microsoft.com/en-us/library/ms345449(v=sql.105).aspx

    .PARAMETER InputObject
        The SMO object to parse

    .PARAMETER AllowSystemObjects
        Normally, system objects are ignored by this function as dependencies.
        This switch overrides that behavior.

    .PARAMETER Parents
        Causes the function to retrieve all objects that the input depends on, rather than retrieving everything that depends on the input.

    .PARAMETER IncludeSelf
        Includes the object whose dependencies are retrieves itself.
        Useful when exporting an entire logic structure in order to recreate it in another database.

    .PARAMETER EnableException
        By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
        This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
        Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.

    .NOTES
        Tags: Dependency, Utility
        Author: Chrissy LeMaire (@cl), netnerds.net

        Website: https://dbatools.io
        Copyright: (c) 2018 by dbatools, licensed under MIT
        License: MIT https://opensource.org/licenses/MIT

    .LINK
        https://dbatools.io/Get-DbaDependency

    .EXAMPLE
        PS C:\> $table = (Get-DbaDatabase -SqlInstance sql2012 -Database Northwind).tables | Where-Object Name -eq Customers
        PS C:\> $table | Get-DbaDependency

        Returns everything that depends on the "Customers" table

    #>
    [CmdletBinding()]
    param (
        [Parameter(ValueFromPipeline)]$InputObject,
        [switch]$AllowSystemObjects,
        [switch]$Parents,
        [switch]$IncludeSelf,
        [switch]$EnableException
    )

    begin {
        #region Utility functions

        function Read-Parent {
            [CmdletBinding()]
            param (
                $InputObject
            )
            $InputObject.Urn
            if ($InputObject.Parent -ne $null) {
                Read-Parent $InputObject.Parent
            }
        }

        function Get-DependencyTree {
            [CmdletBinding()]
            param (
                $Object,

                $Server,

                [bool]
                $AllowSystemObjects,

                [bool]
                $EnumParents,

                [string]
                $FunctionName
            )

            $scripter = New-Object Microsoft.SqlServer.Management.Smo.Scripter
            $options = New-Object Microsoft.SqlServer.Management.Smo.ScriptingOptions
            $options.DriAll = $true
            $options.AllowSystemObjects = $AllowSystemObjects
            $options.WithDependencies = $true
            $scripter.Options = $options
            $scripter.Server = $Server

            $urnCollection = New-Object Microsoft.SqlServer.Management.Smo.UrnCollection

            Write-Message -Level 5 -Message "Adding $Object which is a $($Object.urn.Type)" -FunctionName $FunctionName
            $urnCollection.Add([Microsoft.SqlServer.Management.Sdk.Sfc.Urn]$Object.urn)

            #now we set up an event listener go get progress reports
            $progressReportEventHandler = [Microsoft.SqlServer.Management.Smo.ProgressReportEventHandler] {
                $name = $_.Current.GetAttribute('Name');
                Write-Message -Level 5 -Message "Analysed $name" -FunctionName $FunctionName
            }
            $scripter.add_DiscoveryProgress($progressReportEventHandler)

            return $scripter.DiscoverDependencies($urnCollection, $EnumParents)
        }

        function Read-DependencyTree {
            [CmdletBinding()]
            param (
                [System.Object]
                $InputObject,

                [int]
                $Tier,

                [System.Object]
                $Parent,

                [bool]
                $EnumParents
            )

            Add-Member -Force -InputObject $InputObject -Name Parent -Value $Parent -MemberType NoteProperty
            if ($EnumParents) { Add-Member -Force -InputObject $InputObject -Name Tier -Value ($Tier * -1) -MemberType NoteProperty -PassThru }
            else { Add-Member -Force -InputObject $InputObject -Name Tier -Value $Tier -MemberType NoteProperty -PassThru }

            $circularReferenceCheck = Read-Parent -InputObject $Parent
            if ($Tier -gt 0 -and $circularReferenceCheck.Value -Contains $InputObject.Urn.Value) {
                Write-Message -Message "Circular Reference detected. $circularReferenceCheck" -Level Warning
                return # End dependency tree descension here.
            }

            if ($InputObject.HasChildNodes) { Read-DependencyTree -InputObject $InputObject.FirstChild -Tier ($Tier + 1) -Parent $InputObject -EnumParents $EnumParents }
            if ($InputObject.NextSibling) { Read-DependencyTree -InputObject $InputObject.NextSibling -Tier $Tier -Parent $Parent -EnumParents $EnumParents }
        }

        function Get-DependencyTreeNodeDetail {
            [CmdletBinding()]
            param (
                [Parameter(ValueFromPipeline)]
                $SmoObject,

                $Server,

                $OriginalResource,

                [bool]
                $AllowSystemObjects
            )

            begin {
                $scripter = New-Object Microsoft.SqlServer.Management.Smo.Scripter
                $options = New-Object Microsoft.SqlServer.Management.Smo.ScriptingOptions
                $options.DriAll = $true
                $options.AllowSystemObjects = $AllowSystemObjects
                $options.WithDependencies = $true
                $scripter.Options = $options
                $scripter.Server = $Server

                $eol = [System.Environment]::NewLine
            }

            process {
                foreach ($Item in $SmoObject) {
                    $richobject = $Server.GetSmoObject($Item.urn)
                    $parent = $Server.GetSmoObject($Item.Parent.Urn)

                    $NewObject = New-Object Dataplat.Dbatools.Database.Dependency
                    $NewObject.ComputerName = $server.ComputerName
                    $NewObject.ServiceName = $server.ServiceName
                    $NewObject.SqlInstance = $server.DomainInstanceName
                    $NewObject.Dependent = $richobject.Name
                    $NewObject.Type = $Item.Urn.Type
                    $NewObject.Owner = $richobject.Owner
                    $NewObject.IsSchemaBound = $richobject.IsSchemaBound
                    $NewObject.Parent = $parent.Name
                    $NewObject.ParentType = $parent.Urn.Type
                    $NewObject.Tier = $Item.Tier
                    $NewObject.Object = $richobject
                    $NewObject.Urn = $richobject.Urn
                    $NewObject.OriginalResource = $OriginalResource

                    $SQLscript = $scripter.EnumScriptWithList($richobject)

                    # I can't remember how to remove these options and their syntax is breaking stuff
                    $SQLscript = $SQLscript -replace "SET ANSI_NULLS ON", ""
                    $SQLscript = $SQLscript -replace "SET QUOTED_IDENTIFIER ON", ""
                    $NewObject.Script = "$SQLscript $($eol)go"

                    $NewObject
                }
            }
        }

        function Select-DependencyPrecedence {
            [CmdletBinding()]
            param (
                [Parameter(ValueFromPipeline)]
                $Dependency
            )

            begin {
                $list = @()
            }
            process {
                foreach ($dep in $Dependency) {
                    # Killing the pipeline is generally a bad idea, but since we have to group and sort things, we have not really a choice
                    $list += $dep
                }
            }
            end {
                $list | Group-Object -Property Object, Tier | ForEach-Object { $_.Group | Sort-Object -Property Tier -Descending | Select-Object -First 1 } | Sort-Object Tier
            }
        }
        #endregion Utility functions
    }
    process {
        foreach ($Item in $InputObject) {
            Write-Message -Level Verbose -Message "Processing: $Item"
            if ($null -eq $Item.urn) {
                Stop-Function -Message "$Item is not a valid SMO object" -Category InvalidData -Continue -Target $Item
            }

            # Find the server object to pass on to the function
            $parent = $Item.parent

            do { $parent = $parent.parent }
            until (($parent.urn.type -eq "Server") -or (-not $parent))

            if (-not $parent) {
                Stop-Function -Message "Failed to find valid server object in input: $Item" -Category InvalidData -Continue -Target $Item
            }

            $server = $parent

            $tree = Get-DependencyTree -Object $Item -AllowSystemObjects $false -Server $server -FunctionName (Get-PSCallStack)[0].COmmand -EnumParents $Parents
            $limitCount = 2
            if ($IncludeSelf) { $limitCount = 1 }
            if ($tree.Count -lt $limitCount) {
                Write-Message -Message "No dependencies detected for $($Item)" -Level Important
                continue
            }

            if ($IncludeSelf) { $resolved = Read-DependencyTree -InputObject $tree.FirstChild -Tier 0 -Parent $tree.FirstChild -EnumParents $Parents }
            else { $resolved = Read-DependencyTree -InputObject $tree.FirstChild.FirstChild -Tier 1 -Parent $tree.FirstChild -EnumParents $Parents }
            $resolved | Get-DependencyTreeNodeDetail -Server $server -OriginalResource $Item -AllowSystemObjects $AllowSystemObjects | Select-DependencyPrecedence
        }
    }
}