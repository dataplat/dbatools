#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Resolves and returns object dependencies for piped SMO objects. Port of public/Get-DbaDependency.ps1;
/// the workflow remains a module-scoped PowerShell compatibility hop.
///
/// A process-only port. IMPORTANT STRUCTURE: the source begin block contains ONLY nested helper-function
/// definitions (Read-Parent, Get-DependencyTree, Read-DependencyTree, Get-DependencyTreeNodeDetail,
/// Select-DependencyPrecedence) - pure definitions with no carried state - and the process block uses them. Because
/// begin and process are separate hop scopes, those definitions are PREPENDED into the process hop so they are in
/// scope for the foreach; they are redefined per pipeline record, which is behaviorally identical (pure defs, no
/// closure over mutable begin state - each nested function takes all inputs as explicit params). Three switches
/// (AllowSystemObjects, Parents, IncludeSelf) are consumed as VALUES (if ($IncludeSelf), -EnumParents $Parents,
/// -AllowSystemObjects $AllowSystemObjects), so they are passed as marshaled bools (.ToBool()) into UNTYPED inner
/// params - typing them [switch] would shift positional binding (switch-in-hop-param law; binding-probed BOUND-OK).
/// The source's (Get-PSCallStack)[0].Command at the -FunctionName argument would resolve to the anonymous hop
/// scriptblock, so it is substituted with the literal "Get-DbaDependency" (matching the source's intent, which is
/// the public command name). Edits: -FunctionName Get-DbaDependency on the four direct process Write-Message/
/// Stop-Function calls (the nested functions' own Write-Message calls are left verbatim - they auto-detect the nested
/// function name or use the passed $FunctionName, identically to source). The two Stop-Function carry -Continue; the
/// one continue is loop-bound. No ShouldProcess. Surface pinned by migration/baselines/Get-DbaDependency.json
/// (InputObject VFP pos0, three non-positional switches, no ShouldProcess).
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaDependency")]
public sealed class GetDbaDependencyCommand : DbaBaseCmdlet
{
    /// <summary>The SMO object(s) to resolve dependencies for (piped in).</summary>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    public object? InputObject { get; set; }

    /// <summary>Include system objects in the dependency resolution.</summary>
    [Parameter]
    public SwitchParameter AllowSystemObjects { get; set; }

    /// <summary>Resolve parent (rather than child) dependencies.</summary>
    [Parameter]
    public SwitchParameter Parents { get; set; }

    /// <summary>Include the object itself in the results.</summary>
    [Parameter]
    public SwitchParameter IncludeSelf { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                return;
            }
            WriteObject(item);
        }, ProcessScript,
            InputObject, AllowSystemObjects.ToBool(), Parents.ToBool(), IncludeSelf.ToBool(),
            EnableException.ToBool(), NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }
    // PS: the source begin block's nested function definitions (VERBATIM) PREPENDED to the process block (VERBATIM),
    // so the helpers are in scope for the foreach. Process edits: -FunctionName Get-DbaDependency on the four direct
    // Write-Message/Stop-Function calls; (Get-PSCallStack)[0].Command -> "Get-DbaDependency" (would otherwise resolve
    // to the hop scriptblock). The three switches arrive as marshaled bools; their inner params are UNTYPED.
    private const string ProcessScript = """
param($InputObject, $AllowSystemObjects, $Parents, $IncludeSelf, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param($InputObject, $AllowSystemObjects, $Parents, $IncludeSelf, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

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

            Write-Message -Level 5 -Message "Adding $Object which is a $($Object.urn.Type)" -FunctionName $FunctionName -ModuleName "dbatools"
            $urnCollection.Add([Microsoft.SqlServer.Management.Sdk.Sfc.Urn]$Object.urn)

            #now we set up an event listener go get progress reports
            $progressReportEventHandler = [Microsoft.SqlServer.Management.Smo.ProgressReportEventHandler] {
                $name = $_.Current.GetAttribute('Name');
                Write-Message -Level 5 -Message "Analysed $name" -FunctionName $FunctionName -ModuleName "dbatools"
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

        foreach ($Item in $InputObject) {
            Write-Message -Level Verbose -Message "Processing: $Item" -FunctionName Get-DbaDependency -ModuleName "dbatools"
            if ($null -eq $Item.urn) {
                Stop-Function -Message "$Item is not a valid SMO object" -Category InvalidData -Continue -Target $Item -FunctionName Get-DbaDependency
            }

            # Find the server object to pass on to the function
            $parent = $Item.parent

            do { $parent = $parent.parent }
            until (($parent.urn.type -eq "Server") -or (-not $parent))

            if (-not $parent) {
                Stop-Function -Message "Failed to find valid server object in input: $Item" -Category InvalidData -Continue -Target $Item -FunctionName Get-DbaDependency
            }

            $server = $parent

            $tree = Get-DependencyTree -Object $Item -AllowSystemObjects $false -Server $server -FunctionName "Get-DbaDependency" -EnumParents $Parents
            $limitCount = 2
            if ($IncludeSelf) { $limitCount = 1 }
            if ($tree.Count -lt $limitCount) {
                Write-Message -Message "No dependencies detected for $($Item)" -Level Important -FunctionName Get-DbaDependency -ModuleName "dbatools"
                continue
            }

            if ($IncludeSelf) { $resolved = Read-DependencyTree -InputObject $tree.FirstChild -Tier 0 -Parent $tree.FirstChild -EnumParents $Parents }
            else { $resolved = Read-DependencyTree -InputObject $tree.FirstChild.FirstChild -Tier 1 -Parent $tree.FirstChild -EnumParents $Parents }
            $resolved | Get-DependencyTreeNodeDetail -Server $server -OriginalResource $Item -AllowSystemObjects $AllowSystemObjects | Select-DependencyPrecedence
        }
} $InputObject $AllowSystemObjects $Parents $IncludeSelf $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1
""";
}
