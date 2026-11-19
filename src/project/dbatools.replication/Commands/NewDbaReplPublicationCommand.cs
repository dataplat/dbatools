#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Creates a SQL Server replication publication (transactional, snapshot, or merge) on an instance
/// already configured as a publisher. Port of public/New-DbaReplPublication.ps1. The whole process
/// body rides ONE VERBATIM module hop per pipeline record: the foreach over SqlInstance, the
/// Get-DbaReplServer lookup (still module-scope PowerShell), the not-a-publisher Stop-Function
/// -Continue guard, and the SMO ReplicationDatabase / TransPublication / MergePublication
/// construction (EnabledTransPublishing / EnabledMergePublishing, the log-reader-agent branch, the
/// publication .Create() + CreateSnapshotAgent()) behind the source's single ShouldProcess gate.
/// $PSCmdlet.ShouldProcess routes to the real cmdlet via $__realCmdlet so -WhatIf/-Confirm and
/// yes/no-to-all persist across records; in-hop Stop-Function/Write-Message carry -FunctionName and
/// read $EnableException from the hop param scope; merged-back 2&gt;&amp;1 records re-emit via
/// WriteError with the silent-$error compensation. No cross-record state (each SqlInstance record is
/// self-contained; every Stop-Function is -Continue, which does not latch). The source's trailing
/// Get-DbaRepPublication refetch is preserved verbatim, including its command-name typo, as it is
/// only reached on the success path. Surface pinned by migration/baselines/New-DbaReplPublication.json.
/// </summary>
[Cmdlet(VerbsCommon.New, "DbaReplPublication", DefaultParameterSetName = "Default", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class NewDbaReplPublicationCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database where the publication will be created and which contains the objects to be replicated.</summary>
    [Parameter(Mandatory = true, Position = 2)]
    [PsStringCast]
    public string Database { get; set; } = null!;

    /// <summary>The unique name for the publication within the database.</summary>
    [Parameter(Mandatory = true, Position = 3)]
    [PsStringCast]
    public string Name { get; set; } = null!;

    /// <summary>The replication method used for distributing data to subscribers.</summary>
    [Parameter(Mandatory = true, Position = 4)]
    [ValidateSet("Snapshot", "Transactional", "Merge")]
    [PsStringCast]
    public string Type { get; set; } = null!;

    /// <summary>The Windows account credentials for the Log Reader Agent (Transactional and Snapshot only).</summary>
    [Parameter(Position = 5)]
    public PSCredential? LogReaderAgentCredential { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

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
        }, BodyScript,
        SqlInstance, SqlCredential, Database, Name, Type, LogReaderAgentCredential,
            EnableException.ToBool(), this, NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // The whole process body VERBATIM in the dbatools module scope: the per-instance foreach, the
    // still-PS Get-DbaReplServer, the not-a-publisher guard, the SMO publication construction behind
    // the single ShouldProcess gate, and the trailing refetch. ShouldProcess routes to the real
    // cmdlet; Stop-Function/Write-Message carry -FunctionName.
    private const string BodyScript = """
param($SqlInstance, $SqlCredential, $Database, $Name, $Type, $LogReaderAgentCredential, $EnableException, $__realCmdlet, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $SqlCredential, $Database, $Name, $Type, $LogReaderAgentCredential, $EnableException, $__realCmdlet)

    foreach ($instance in $SqlInstance) {
        try {
            $replServer = Get-DbaReplServer -SqlInstance $instance -SqlCredential $SqlCredential -EnableException:$EnableException

            if (-not $replServer.IsPublisher) {
                Stop-Function -Message "Instance $instance is not a publisher, run Enable-DbaReplPublishing to set this up" -Target $instance -Continue -FunctionName New-DbaReplPublication
            }

        } catch {
            Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName New-DbaReplPublication
        }
        Write-Message -Level Verbose -Message "Creating publication on $instance" -FunctionName New-DbaReplPublication -ModuleName "dbatools"

        try {
            if ($__realCmdlet.ShouldProcess($instance, "Creating publication on $instance")) {



                $pubDatabase = New-Object Microsoft.SqlServer.Replication.ReplicationDatabase
                $pubDatabase.ConnectionContext = $replServer.ConnectionContext
                $pubDatabase.Name = $Database
                if (-not $pubDatabase.LoadProperties()) {
                    throw "Database $Database not found on $instance"
                }

                if ($Type -in ('Transactional', 'Snapshot')) {
                    Write-Message -Level Verbose -Message "Enable trans publishing publication on $instance.$Database" -FunctionName New-DbaReplPublication -ModuleName "dbatools"
                    $pubDatabase.EnabledTransPublishing = $true
                    $pubDatabase.CommitPropertyChanges()
                    # log reader agent is only needed for transactional and snapshot replication.
                    if (-not $pubDatabase.LogReaderAgentExists) {
                        Write-Message -Level Verbose -Message "Create log reader agent job for $Database on $instance" -FunctionName New-DbaReplPublication -ModuleName "dbatools"
                        if ($LogReaderAgentCredential) {
                            $pubDatabase.LogReaderAgentProcessSecurity.Login = $LogReaderAgentCredential.UserName
                            $pubDatabase.LogReaderAgentProcessSecurity.Password = $LogReaderAgentCredential.Password
                        }

                        #(Optional) Set the SqlStandardLogin and SqlStandardPassword or
                        # SecureSqlStandardPassword fields of LogReaderAgentPublisherSecurity when using SQL Server Authentication to connect to the Publisher.

                        $pubDatabase.CreateLogReaderAgent()
                    } else {
                        Write-Message -Level Verbose -Message "Log reader agent job already exists for $Database on $instance" -FunctionName New-DbaReplPublication -ModuleName "dbatools"
                    }

                } elseif ($Type -eq 'Merge') {
                    Write-Message -Level Verbose -Message "Enable merge publishing publication on $instance.$Database" -FunctionName New-DbaReplPublication -ModuleName "dbatools"
                    $pubDatabase.EnabledMergePublishing = $true
                    $pubDatabase.CommitPropertyChanges()
                }

                if ($Type -in ('Transactional', 'Snapshot')) {

                    $transPub = New-Object Microsoft.SqlServer.Replication.TransPublication
                    $transPub.ConnectionContext = $replServer.ConnectionContext
                    $transPub.DatabaseName = $Database
                    $transPub.Name = $Name
                    $transPub.Type = $Type
                    $transPub.Create()

                    # create the Snapshot Agent job
                    $transPub.CreateSnapshotAgent()

                    <#
                    TODO: add SnapshotGenerationAgentProcessSecurity creds in?

                    The Login and Password fields of SnapshotGenerationAgentProcessSecurity to provide the credentials for the Windows account under which the Snapshot Agent runs.
                    This account is also used when the Snapshot Agent makes connections to the local Distributor and for any remote connections when using Windows Authentication.

                    Note
                    Setting SnapshotGenerationAgentProcessSecurity is not required when the publication is created by a member of the sysadmin fixed server role.
                    In this case, the agent will impersonate the SQL Server Agent account. For more information, see Replication Agent Security Model.

                    (Optional) The SqlStandardLogin and SqlStandardPassword or
                    SecureSqlStandardPassword fields of SnapshotGenerationAgentPublisherSecurity when using SQL Server Authentication to connect to the Publisher.
                    #>
                } elseif ($Type -eq 'Merge') {
                    $mergePub = New-Object Microsoft.SqlServer.Replication.MergePublication
                    $mergePub.ConnectionContext = $replServer.ConnectionContext
                    $mergePub.DatabaseName = $Database
                    $mergePub.Name = $Name
                    $mergePub.Create()

                    # create the Snapshot Agent job
                    $mergePub.CreateSnapshotAgent()

                    <#
                    TODO: add SnapshotGenerationAgentProcessSecurity creds in?

                    The Login and Password fields of SnapshotGenerationAgentProcessSecurity to provide the credentials for the Windows account under which the Snapshot Agent runs.
                    This account is also used when the Snapshot Agent makes connections to the local Distributor and for any remote connections when using Windows Authentication.

                    Note
                    Setting SnapshotGenerationAgentProcessSecurity is not required when the publication is created by a member of the sysadmin fixed server role.
                    For more information, see Replication Agent Security Model.

                    (Optional) Use the inclusive logical OR operator (| in Visual C# and Or in Visual Basic) and the exclusive logical OR operator (^ in Visual C# and Xor in Visual Basic)
                    to set the PublicationAttributes values for the Attributes property.

                    #>
                }
            }
        } catch {
            Stop-Function -Message ("Unable to create publication - {0}" -f $_) -ErrorRecord $_ -Target $instance -Continue -FunctionName New-DbaReplPublication
        }
        Get-DbaRepPublication -SqlInstance $instance -SqlCredential $SqlCredential -Database $Database -Name $Name
    }
} $SqlInstance $SqlCredential $Database $Name $Type $LogReaderAgentCredential $EnableException $__realCmdlet @__commonParameters 3>&1 2>&1
""";
}
