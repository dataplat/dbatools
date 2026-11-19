#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Removes a replication subscription (push, transactional/snapshot or merge) from a subscriber
/// instance. Port of public/Remove-DbaReplSubscription.ps1. The source's begin block (connect to
/// the publisher via Get-DbaReplPublication and warn when the named publication is not found) and
/// its process block (the per-subscriber foreach that constructs the SMO
/// TransSubscription/MergeSubscription and calls .Remove() behind the ShouldProcess gate) ride ONE
/// VERBATIM module hop per pipeline record: the whole body runs inside the dbatools module scope so
/// the RMO New-Object and the nested Get-DbaReplPublication resolve exactly as the retired function
/// saw them. $PSCmdlet.ShouldProcess routes to the real cmdlet via $__realCmdlet so -WhatIf/-Confirm
/// persist; the in-hop Write-Message calls carry -FunctionName/-ModuleName and the catch's
/// Stop-Function carries -FunctionName and is -Continue (does not latch), so no C# latch carrier is
/// needed. The begin-block Write-Warning ("Didn't find a subscription to the &lt;publication&gt;
/// publication") merges back through the hop and re-emits on the host warning stream. Surface pinned
/// by migration/baselines/Remove-DbaReplSubscription.json (no DefaultParameterSetName - the source
/// declares none).
/// </summary>
[Cmdlet(VerbsCommon.Remove, "DbaReplSubscription", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.High)]
public sealed class RemoveDbaReplSubscriptionCommand : DbaBaseCmdlet
{
    /// <summary>The target publisher SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target publisher instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The publisher database that contains the replication publication.</summary>
    [Parameter(Mandatory = true, Position = 2)]
    [PsStringCast]
    public string Database { get; set; } = null!;

    /// <summary>The name of the replication publication to remove the subscription from.</summary>
    [Parameter(Mandatory = true, Position = 3)]
    [PsStringCast]
    public string PublicationName { get; set; } = null!;

    /// <summary>The subscriber SQL Server instance that receives replicated data.</summary>
    [Parameter(Mandatory = true, Position = 4)]
    public DbaInstanceParameter SubscriberSqlInstance { get; set; } = null!;

    /// <summary>Login to the subscriber instance using alternative credentials.</summary>
    [Parameter(Position = 5)]
    public PSCredential? SubscriberSqlCredential { get; set; }

    /// <summary>The database on the subscriber that receives the replicated data.</summary>
    [Parameter(Mandatory = true, Position = 6)]
    [PsStringCast]
    public string SubscriptionDatabase { get; set; } = null!;

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
        SqlInstance, SqlCredential, Database, PublicationName, SubscriberSqlInstance,
            SubscriberSqlCredential, SubscriptionDatabase, EnableException.ToBool(), this,
            NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // The source begin+process body VERBATIM in the dbatools module scope: the publisher lookup and
    // not-found warning, then the per-subscriber foreach with the SMO subscription construction and
    // .Remove() behind the source's ShouldProcess gate. ShouldProcess routes to the real cmdlet;
    // Write-Message/Stop-Function carry -FunctionName. The undefined $instance the source would
    // interpolate is scoped by the foreach here exactly as the source's process block scoped it.
    private const string BodyScript = """
param($SqlInstance, $SqlCredential, $Database, $PublicationName, $SubscriberSqlInstance, $SubscriberSqlCredential, $SubscriptionDatabase, $EnableException, $__realCmdlet, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $SqlCredential, $Database, $PublicationName, [Dataplat.Dbatools.Parameter.DbaInstanceParameter]$SubscriberSqlInstance, $SubscriberSqlCredential, $SubscriptionDatabase, $EnableException, $__realCmdlet)

    $pub = Get-DbaReplPublication -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Name $PublicationName -EnableException:$EnableException

    if (-not $pub) {
        Write-Warning "Didn't find a subscription to the $PublicationName publication on $SqlInstance.$Database"
    }

    foreach ($instance in $SubscriberSqlInstance) {

        try {
            if ($__realCmdlet.ShouldProcess($instance, "Removing subscription to $PublicationName from $SqlInstance.$SubscriptionDatabase")) {

                if ($pub.Type -in ('Transactional', 'Snapshot')) {

                    #TODO: Only handles push subscriptions at the moment - need to add pull subscriptions
                    # https://learn.microsoft.com/en-us/sql/relational-databases/replication/delete-a-pull-subscription?view=sql-server-ver16
                    $transSub = New-Object Microsoft.SqlServer.Replication.TransSubscription
                    $transSub.ConnectionContext = $pub.ConnectionContext
                    $transSub.DatabaseName = $Database
                    $transSub.PublicationName = $PublicationName
                    $transSub.SubscriptionDBName = $SubscriptionDatabase
                    $transSub.SubscriberName = $instance

                    if ($transSub.IsExistingObject) {
                        Write-Message -Level Verbose -Message "Removing the subscription" -FunctionName Remove-DbaReplSubscription -ModuleName "dbatools"
                        $transSub.Remove()
                    }

                } elseif ($pub.Type -eq 'Merge') {
                    $mergeSub = New-Object Microsoft.SqlServer.Replication.MergeSubscription
                    $mergeSub.ConnectionContext = $pub.ConnectionContext
                    $mergeSub.DatabaseName = $Database
                    $mergeSub.PublicationName = $PublicationName
                    $mergeSub.SubscriptionDBName = $SubscriptionDatabase
                    $mergeSub.SubscriberName = $instance

                    if ($mergeSub.IsExistingObject) {
                        Write-Message -Level Verbose -Message "Removing the merge subscription" -FunctionName Remove-DbaReplSubscription -ModuleName "dbatools"
                        $mergeSub.Remove()
                    } else {
                        Write-Warning "Didn't find a subscription to $PublicationName on $($instance).$SubscriptionDatabase"
                    }
                }
            }
        } catch {
            Stop-Function -Message ("Unable to remove subscription - {0}" -f $_) -ErrorRecord $_ -Target $instance -Continue -FunctionName Remove-DbaReplSubscription
        }
    }
} $SqlInstance $SqlCredential $Database $PublicationName $SubscriberSqlInstance $SubscriberSqlCredential $SubscriptionDatabase $EnableException $__realCmdlet @__commonParameters 3>&1 2>&1
""";
}
