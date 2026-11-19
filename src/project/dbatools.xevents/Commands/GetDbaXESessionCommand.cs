#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves Extended Events sessions with their configuration and status from one or more SQL Server
/// instances.
/// </summary>
/// <remarks>
/// The connection, the XEStore construction, the session enumeration and -Session filter, the target-file
/// path resolution, the Add-Member decoration, and the Select-DefaultView projection all run the original
/// dbatools PowerShell body VERBATIM inside the dbatools module scope rather than being reimplemented in
/// C#, so the engine decides the observable details.
///
/// The function is process-only with a single foreach over the instances; the sole Stop-Function (connect
/// failure) is -Continue, so there is no begin/end block, no interrupt (nothing reads Test-FunctionInterrupt,
/// and -Continue never sets one), no ShouldProcess and no Test-Bound - and therefore no Interrupted guard
/// (the base flag is never set by a hop). Each session is emitted before a later instance may fail under
/// -EnableException (DEF-001), so the process hop uses InvokeScopedStreaming. Surface pinned by
/// migration/baselines/Get-DbaXESession.json.
/// </remarks>
[Cmdlet(VerbsCommon.Get, "DbaXESession")]
public sealed class GetDbaXESessionCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    [PsDbaInstanceArrayCast]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Filters results to specific Extended Events sessions by name.</summary>
    [Parameter(Position = 2)]
    [Alias("Sessions")]
    public object[]? Session { get; set; }

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
            SqlInstance, SqlCredential, Session, EnableException.ToBool(),
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // PS: the process block VERBATIM apart from -FunctionName Get-DbaXESession on the direct Stop-Function
    // and Write-Message sites.
    private const string ProcessScript = """
param($SqlInstance, $SqlCredential, $Session, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $SqlCredential, [object[]]$Session, $EnableException)
    foreach ($instance in $SqlInstance) {
        try {
            $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential -MinimumVersion 11 -AzureUnsupported
            $SqlConn = $server.ConnectionContext.SqlConnectionObject.Clone()
            $SqlStoreConnection = New-Object Microsoft.SqlServer.Management.Sdk.Sfc.SqlStoreConnection $SqlConn
            $XEStore = New-Object  Microsoft.SqlServer.Management.XEvent.XEStore $SqlStoreConnection
        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Get-DbaXESession
        }

        Write-Message -Level Verbose -Message "Getting XEvents Sessions on $instance." -FunctionName Get-DbaXESession -ModuleName "dbatools"
        $xesessions = $XEStore.sessions

        if ($Session) {
            $xesessions = $xesessions | Where-Object { $_.Name -in $Session }
        }

        foreach ($x in $xesessions) {
            $status = switch ($x.IsRunning) { $true { "Running" } $false { "Stopped" } }
            $files = $x.Targets.TargetFields | Where-Object Name -eq Filename | Select-Object -ExpandProperty Value

            $filecollection = $remotefile = @()

            if ($files) {
                foreach ($file in $files) {
                    if ($file -notmatch ':\\' -and $file -notmatch '\\\\' -and $file -notmatch '\/') {
                        $directory = $server.ErrorLogPath.TrimEnd("\/")
                        $file = (Join-DbaPath -SqlInstance $server $directory $file)
                    }
                    $filecollection += $file
                    $remotefile += Join-AdminUnc -servername $server.ComputerName -filepath $file
                }
            }

            Add-Member -Force -InputObject $x -MemberType NoteProperty -Name ComputerName -Value $server.ComputerName
            Add-Member -Force -InputObject $x -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
            Add-Member -Force -InputObject $x -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName
            Add-Member -Force -InputObject $x -MemberType NoteProperty -Name Status -Value $status
            Add-Member -Force -InputObject $x -MemberType NoteProperty -Name Session -Value $x.Name
            Add-Member -Force -InputObject $x -MemberType NoteProperty -Name TargetFile -Value $filecollection
            Add-Member -Force -InputObject $x -MemberType NoteProperty -Name RemoteTargetFile -Value $remotefile
            Add-Member -Force -InputObject $x -MemberType NoteProperty -Name Parent -Value $server
            Add-Member -Force -InputObject $x -MemberType NoteProperty -Name Store -Value $XEStore
            Select-DefaultView -InputObject $x -Property ComputerName, InstanceName, SqlInstance, Name, Status, StartTime, AutoStart, State, Targets, TargetFile, Events, MaxMemory, MaxEventSize
        }
    }
} $SqlInstance $SqlCredential $Session $EnableException @__commonParameters 3>&1 2>&1
""";
}
