#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves the Extended Events store (XEStore) object for one or more SQL Server instances.
/// </summary>
/// <remarks>
/// The connection, the XEStore construction, the Add-Member decoration, and the Select-DefaultView
/// projection all run the original dbatools PowerShell body VERBATIM inside the dbatools module scope
/// rather than being reimplemented in C#, so the engine decides the observable details.
///
/// The function is process-only with a single foreach over the instances; a connect failure is a
/// -Continue Stop-Function (never sets the interrupt), so there is no begin/end block, no interrupt
/// carry, no ShouldProcess and no Test-Bound. Each instance's store is emitted before a later instance
/// may fail under -EnableException (DEF-001), so the process hop uses InvokeScopedStreaming. Surface
/// pinned by migration/baselines/Get-DbaXEStore.json.
/// </remarks>
[Cmdlet(VerbsCommon.Get, "DbaXEStore")]
public sealed class GetDbaXEStoreCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [PsDbaInstanceArrayCast]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - the source declares it bare (every set), which
    // the inherited [Parameter] (no ParameterSetName) already matches; no override needed.

    protected override void ProcessRecord()
    {
        NestedCommand.InvokeScopedStreaming(this, item =>
        {
            if (item?.BaseObject is ErrorRecord nestedError)
            {
                NestedCommand.RemoveDuplicateError(this, nestedError);
                WriteError(NestedCommand.PreserveErrorIdentity(nestedError));
            }
            else
            {
                WriteObject(item);
            }
        }, ProcessScript,
            SqlInstance, SqlCredential, EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the process block VERBATIM apart from -FunctionName Get-DbaXEStore on the direct Stop-Function.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $SqlCredential, $EnableException)
    foreach ($instance in $SqlInstance) {
        try {
            $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 11
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Get-DbaXEStore
        }

        $SqlConn = $server.ConnectionContext.SqlConnectionObject
        $SqlStoreConnection = New-Object Microsoft.SqlServer.Management.Sdk.Sfc.SqlStoreConnection $SqlConn
        $store = New-Object  Microsoft.SqlServer.Management.XEvent.XEStore $SqlStoreConnection

        Add-Member -Force -InputObject $store -MemberType NoteProperty -Name ComputerName -Value $server.ComputerName
        Add-Member -Force -InputObject $store -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
        Add-Member -Force -InputObject $store -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName
        Select-DefaultView -InputObject $store -Property ComputerName, InstanceName, SqlInstance, ServerName, Sessions, Packages, RunningSessionCount
    }
} $SqlInstance $SqlCredential $EnableException @__commonParameters 3>&1 2>&1
""";
}
