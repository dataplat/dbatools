#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves database master keys from one or more SQL Server databases.
/// </summary>
/// <remarks>
/// <para>
/// The workflow remains a module-scoped PowerShell compatibility hop so that database enumeration, the
/// master-key retrieval, the added note properties, the default view, and dbatools stream and error
/// handling stay observable-identical to the script implementation.
/// </para>
/// <para>
/// The command is process-only, so it ships as a single hop per record. Database objects piped through
/// InputObject bind per record; when SqlInstance is supplied instead, the body appends the resolved
/// databases to InputObject within that record - so no cross-record state is carried. The body has no
/// Stop-Function, try/catch, or other terminating path (only Write-Message warnings and continue), so
/// there is no earlier-output-before-later-throw exposure and buffered InvokeScoped is correct.
/// EnableException is carried into the hop as a plain (untyped) value, because a switch in the inner
/// CmdletBinding scriptblock is excluded from positional binding.
/// </para>
/// </remarks>
[Cmdlet(VerbsCommon.Get, "DbaDbMasterKey")]
[OutputType(typeof(Microsoft.SqlServer.Management.Smo.MasterKey))]
public sealed class GetDbaDbMasterKeyCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database or databases to scan for master keys.</summary>
    [Parameter(Position = 2)]
    public string[]? Database { get; set; }

    /// <summary>Databases to exclude from the scan.</summary>
    [Parameter(Position = 3)]
    public string[]? ExcludeDatabase { get; set; }

    /// <summary>Database objects, typically piped from Get-DbaDatabase.</summary>
    [Parameter(ValueFromPipeline = true, Position = 4)]
    public Microsoft.SqlServer.Management.Smo.Database[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    /// <summary>Retrieves master keys for one pipeline record.</summary>
    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        foreach (PSObject? item in NestedCommand.InvokeScoped(this, ProcessScript,
            SqlInstance, SqlCredential, Database, ExcludeDatabase, InputObject,
            EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug")))
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
                continue;
            }
            WriteObject(item);
        }
    }

    // PS: the process body VERBATIM. Substitutions only: -FunctionName on the two direct Write-Message
    // calls (no nested named helper; no Stop-Function; no ShouldProcess). EnableException is received as
    // a plain (untyped) param - never re-typed [switch] - because a [switch] in the inner [CmdletBinding()]
    // scriptblock is excluded from positional binding.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Database, $ExcludeDatabase, $InputObject, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -lt 7) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, [System.Management.Automation.PSCredential]$SqlCredential, [string[]]$Database, [string[]]$ExcludeDatabase, [Microsoft.SqlServer.Management.Smo.Database[]]$InputObject, $EnableException, $__boundVerbose, $__boundDebug)
    if ($null -ne $__boundDebug -and $PSVersionTable.PSVersion.Major -ge 7) { $DebugPreference = $(if ($__boundDebug) { "Continue" } else { "SilentlyContinue" }) }

        if ($SqlInstance) {
            $InputObject += Get-DbaDatabase -SqlInstance $SqlInstance -Database $Database -ExcludeDatabase $ExcludeDatabase -SqlCredential $SqlCredential
        }

        foreach ($db in $InputObject) {
            if (!$db.IsAccessible) {
                Write-Message -Level Warning -Message "Database $db on $($db.Parent) is not accessible. Skipping." -FunctionName Get-DbaDbMasterKey -ModuleName "dbatools"
                continue
            }
            $instance = $db.Parent.Name
            $masterkey = $db.MasterKey

            if (!$masterkey) {
                Write-Message -Message "No master key exists in the $db database on $instance" -Target $db -Level Verbose -FunctionName Get-DbaDbMasterKey -ModuleName "dbatools"
                continue
            }

            Add-Member -Force -InputObject $masterkey -MemberType NoteProperty -Name ComputerName -value $db.Parent.ComputerName
            Add-Member -Force -InputObject $masterkey -MemberType NoteProperty -Name InstanceName -value $db.Parent.ServiceName
            Add-Member -Force -InputObject $masterkey -MemberType NoteProperty -Name SqlInstance -value $db.Parent.DomainInstanceName
            Add-Member -Force -InputObject $masterkey -MemberType NoteProperty -Name Database -value $db.Name

            Select-DefaultView -InputObject $masterkey -Property ComputerName, InstanceName, SqlInstance, Database, CreateDate, DateLastModified, IsEncryptedByServer
        }
} $SqlInstance $SqlCredential $Database $ExcludeDatabase $InputObject $EnableException $__boundVerbose $__boundDebug @__commonParameters 3>&1 2>&1

""";
}
