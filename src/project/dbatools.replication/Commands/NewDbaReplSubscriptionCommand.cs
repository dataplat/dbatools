#nullable enable

using System;
using System.Collections;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Creates SQL Server replication subscriptions (push or pull) connecting a subscriber to an
/// existing publication on a publisher. Port of public/New-DbaReplSubscription.ps1. The whole
/// begin+process body rides ONE VERBATIM module hop per pipeline record: the publisher connect
/// (Get-DbaReplServer), the publication lookup (Get-DbaReplPublication), and the per-subscriber
/// foreach that creates the subscription database if absent (New-DbaDatabase), the required
/// schemas (New-DbaDbSchema), and the SMO TransPublication/TransSubscription (or Merge
/// equivalents) construction behind the source's two ShouldProcess gates. $PSCmdlet.ShouldProcess
/// routes to the real cmdlet via $__realCmdlet so -WhatIf/-Confirm and yes/no-to-all persist;
/// in-hop Stop-Function/Write-Message carry -FunctionName and read $EnableException from the hop
/// param scope; merged-back 2&gt;&amp;1 records re-emit via WriteError with the silent-$error
/// compensation. Every Stop-Function is -Continue (does not latch). The source's merge-branch
/// $type-assignment bugs (`if ($type = 'Push')`) are preserved verbatim per bug-for-bug parity.
/// Surface pinned by migration/baselines/New-DbaReplSubscription.json.
/// </summary>
[Cmdlet(VerbsCommon.New, "DbaReplSubscription", DefaultParameterSetName = "Default", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
public sealed class NewDbaReplSubscriptionCommand : DbaBaseCmdlet
{
    /// <summary>The target publishing SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter SqlInstance { get; set; } = null!;

    /// <summary>Login to the target publishing instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The source database on the publisher that contains the publication data.</summary>
    [Parameter(Position = 2)]
    public string? Database { get; set; }

    /// <summary>The target SQL Server instance that will receive the replicated data.</summary>
    [Parameter(Mandatory = true, Position = 3)]
    public DbaInstanceParameter[] SubscriberSqlInstance { get; set; } = null!;

    /// <summary>Login credentials for connecting to the subscriber SQL Server instance.</summary>
    [Parameter(Position = 4)]
    public PSCredential? SubscriberSqlCredential { get; set; }

    /// <summary>The destination database name on the subscriber where replicated data will be stored.</summary>
    [Parameter(Position = 5)]
    public string? SubscriptionDatabase { get; set; }

    /// <summary>The name of the existing publication on the publisher database to subscribe to.</summary>
    [Parameter(Mandatory = true, Position = 6)]
    [PsStringCast]
    public string PublicationName { get; set; } = null!;

    /// <summary>SQL Server credentials used by the replication agents to connect to the subscriber.</summary>
    [Parameter(Position = 7)]
    public PSCredential? SubscriptionSqlCredential { get; set; }

    /// <summary>Specifies whether to create a Push or Pull subscription for data synchronization.</summary>
    [Parameter(Mandatory = true, Position = 8)]
    [ValidateSet("Push", "Pull")]
    [PsStringCast]
    public string Type { get; set; } = null!;

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
        SqlInstance, SqlCredential, Database, SubscriberSqlInstance, SubscriberSqlCredential,
            SubscriptionDatabase, PublicationName, SubscriptionSqlCredential, Type,
            EnableException.ToBool(), this, NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // The source begin+process body VERBATIM in the dbatools module scope: the publisher connect and
    // publication lookup, then the per-subscriber foreach with the subscription-database/schema
    // creation and the SMO subscription construction behind the source's two ShouldProcess gates.
    // ShouldProcess routes to the real cmdlet; Stop-Function/Write-Message carry -FunctionName.
    private const string BodyScript = """
param($SqlInstance, $SqlCredential, $Database, $SubscriberSqlInstance, $SubscriberSqlCredential, $SubscriptionDatabase, $PublicationName, $SubscriptionSqlCredential, $Type, $EnableException, $__realCmdlet, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter]$SqlInstance, $SqlCredential, $Database, [Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SubscriberSqlInstance, $SubscriberSqlCredential, $SubscriptionDatabase, $PublicationName, $SubscriptionSqlCredential, $Type, $EnableException, $__realCmdlet)

    Write-Message -Level Verbose -Message "Connecting to publisher: $SqlInstance" -FunctionName New-DbaReplSubscription -ModuleName "dbatools"

    # connect to publisher and get the publication
    try {
        $pubReplServer = Get-DbaReplServer -SqlInstance $SqlInstance -SqlCredential $SqlCredential -EnableException:$EnableException
    } catch {
        Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $SqlInstance -Continue -FunctionName New-DbaReplSubscription
    }

    try {
        $pub = Get-DbaReplPublication -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Name $PublicationName -EnableException:$EnableException
    } catch {
        Stop-Function -Message ("Publication {0} not found on {1}" -f $PublicationName, $SqlInstance) -ErrorRecord $_ -Target $SqlInstance -Continue -FunctionName New-DbaReplSubscription
    }

    # for each subscription SqlInstance we need to create a subscription
    foreach ($instance in $SubscriberSqlInstance) {

        try {
            $subReplServer = Get-DbaReplServer -SqlInstance $instance -SqlCredential $SubscriberSqlCredential -EnableException:$EnableException

            if (-not (Get-DbaDatabase -SqlInstance $instance -SqlCredential $SubscriberSqlCredential -Database $SubscriptionDatabase -EnableException:$EnableException)) {

                Write-Message -Level Verbose -Message "Subscription database $SubscriptionDatabase not found on $instance - will create it - but you should check the settings!" -FunctionName New-DbaReplSubscription -ModuleName "dbatools"

                if ($__realCmdlet.ShouldProcess($instance, "Creating subscription database")) {

                    $newSubDb = @{
                        SqlInstance     = $instance
                        SqlCredential   = $SubscriberSqlCredential
                        Name            = $SubscriptionDatabase
                        EnableException = $EnableException
                    }
                    $null = New-DbaDatabase @newSubDb
                }
            }
        } catch {
            Stop-Function -Message ("Couldn't create the subscription database {0}.{1}" -f $instance, $SubscriptionDatabase) -ErrorRecord $_ -Target $instance -Continue -FunctionName New-DbaReplSubscription
        }

        try {
            Write-Message -Level Verbose -Message "Creating subscription on $instance" -FunctionName New-DbaReplSubscription -ModuleName "dbatools"
            if ($__realCmdlet.ShouldProcess($instance, "Creating subscription on $instance")) {

                # check if needed schemas exist
                foreach ($schema in $pub.articles.DestinationObjectOwner) {
                    if ($schema -ne 'dbo' -and -not (Get-DbaDbSchema -SqlInstance $instance -SqlCredential $SubscriberSqlCredential -Database $SubscriptionDatabase -Schema $schema)) {
                        Write-Message -Level Verbose -Message "Subscription database $SubscriptionDatabase does not contain the $schema schema on $instance - will create it!" -FunctionName New-DbaReplSubscription -ModuleName "dbatools"
                        $null = New-DbaDbSchema -SqlInstance $instance -SqlCredential $SubscriberSqlCredential -Database $SubscriptionDatabase -Schema $schema -EnableException
                    }
                }

                if ($pub.Type -in ('Transactional', 'Snapshot')) {

                    $transPub = New-Object Microsoft.SqlServer.Replication.TransPublication
                    $transPub.ConnectionContext = $pubReplServer.ConnectionContext
                    $transPub.DatabaseName = $Database
                    $transPub.Name = $PublicationName

                    # if LoadProperties returns then the publication was found
                    if ( $transPub.LoadProperties() ) {

                        if ($type -eq 'Push') {

                            # Perform a bitwise logical AND (& in Visual C# and And in Visual Basic) between the Attributes property and AllowPush.
                            if (($transPub.Attributes -band [Microsoft.SqlServer.Replication.PublicationAttributes]::AllowPush) -ne [Microsoft.SqlServer.Replication.PublicationAttributes]::AllowPush) {

                                # # Perform a bitwise logical AND (& in Visual C# and And in Visual Basic) between the Attributes property and AllowPush.
                                # if ($transPub.Attributes -band 'AllowPush' -eq 'None' ) {

                                # If the result is None, set Attributes to the result of a bitwise logical OR (| in Visual C# and Or in Visual Basic) between Attributes and AllowPush.
                                $transPub.Attributes = $transPub.Attributes -bor 'AllowPush'

                                # Then, call CommitPropertyChanges to enable push subscriptions.
                                $transPub.CommitPropertyChanges()
                            }
                        } else {
                            #TODO: Fix pull subscriptions in New-DbaReplSubscription command - this still creates a PUSH

                            # Perform a bitwise logical AND (& in Visual C# and And in Visual Basic) between the Attributes property and AllowPull.
                            if (($transPub.Attributes -band [Microsoft.SqlServer.Replication.PublicationAttributes]::AllowPull) -ne [Microsoft.SqlServer.Replication.PublicationAttributes]::AllowPull) {
                                # If the result is None, set Attributes to the result of a bitwise logical OR (| in Visual C# and Or in Visual Basic) between Attributes and AllowPull.
                                $transPub.Attributes = $transPub.Attributes -bor 'AllowPull'

                                # Then, call CommitPropertyChanges to enable pull subscriptions.
                                $transPub.CommitPropertyChanges()
                            }
                        }

                        # create the subscription
                        $transSub = New-Object Microsoft.SqlServer.Replication.TransSubscription
                        $transSub.ConnectionContext = $pubReplServer.ConnectionContext
                        $transSub.SubscriptionDBName = $SubscriptionDatabase
                        $transSub.SubscriberName = $instance
                        $transSub.DatabaseName = $Database
                        $transSub.PublicationName = $PublicationName

                        #TODO:

                        <#
                        The Login and Password fields of SynchronizationAgentProcessSecurity to provide the credentials for the
                        Microsoft Windows account under which the Distribution Agent runs at the Distributor. This account is used to make local connections to the Distributor and to make
                        remote connections by using Windows Authentication.

                        Note
                        Setting SynchronizationAgentProcessSecurity is not required when the subscription is created by a member of the sysadmin fixed server role, but we recommend it.
                        In this case, the agent will impersonate the SQL Server Agent account. For more information, see Replication Agent security model.

                        (Optional) A value of true (the default) for CreateSyncAgentByDefault to create an agent job that is used to synchronize the subscription.
                        If you specify false, the subscription can only be synchronized programmatically.

                        #>

                        if ($SubscriptionSqlCredential) {
                            $transSub.SubscriberSecurity.WindowsAuthentication = $false
                            $transSub.SubscriberSecurity.SqlStandardLogin = $SubscriptionSqlCredential.UserName
                            $transSub.SubscriberSecurity.SecureSqlStandardPassword = $SubscriptionSqlCredential.Password
                        }

                        $transSub.Create()
                    } else {
                        Stop-Function -Message ("Publication {0} not found on {1}" -f $PublicationName, $instance) -Target $instance -Continue -FunctionName New-DbaReplSubscription
                    }

                } elseif ($pub.Type -eq 'Merge') {

                    $mergePub = New-Object Microsoft.SqlServer.Replication.MergePublication
                    $mergePub.ConnectionContext = $pubReplServer.ConnectionContext
                    $mergePub.DatabaseName = $Database
                    $mergePub.Name = $PublicationName

                    if ( $mergePub.LoadProperties() ) {

                        if ($type = 'Push') {
                            # Perform a bitwise logical AND (& in Visual C# and And in Visual Basic) between the Attributes property and AllowPush.
                            if ($mergePub.Attributes -band 'AllowPush' -eq 'None' ) {
                                # If the result is None, set Attributes to the result of a bitwise logical OR (| in Visual C# and Or in Visual Basic) between Attributes and AllowPush.
                                $mergePub.Attributes = $mergePub.Attributes -bor 'AllowPush'

                                # Then, call CommitPropertyChanges to enable push subscriptions.
                                $mergePub.CommitPropertyChanges()
                            }

                        } else {
                            # Perform a bitwise logical AND (& in Visual C# and And in Visual Basic) between the Attributes property and AllowPull.
                            if ($mergePub.Attributes -band 'AllowPull' -eq 'None' ) {
                                # If the result is None, set Attributes to the result of a bitwise logical OR (| in Visual C# and Or in Visual Basic) between Attributes and AllowPull.
                                $mergePub.Attributes = $mergePub.Attributes -bor 'AllowPull'

                                # Then, call CommitPropertyChanges to enable pull subscriptions.
                                $mergePub.CommitPropertyChanges()
                            }
                        }

                        # create the subscription
                        if ($type = 'Push') {
                            $mergeSub = New-Object Microsoft.SqlServer.Replication.MergeSubscription
                        } else {
                            $mergeSub = New-Object Microsoft.SqlServer.Replication.MergePullSubscription
                        }

                        $mergeSub.ConnectionContext = $pubReplServer.ConnectionContext
                        $mergeSub.SubscriptionDBName = $SubscriptionDatabase
                        $mergeSub.SubscriberName = $instance
                        $mergeSub.DatabaseName = $Database
                        $mergeSub.PublicationName = $PublicationName

                        #TODO:

                        <#
                        The Login and Password fields of SynchronizationAgentProcessSecurity to provide the credentials for the
                        Microsoft Windows account under which the Distribution Agent runs at the Distributor. This account is used to make local connections to the Distributor and to make
                        remote connections by using Windows Authentication.

                        Note
                        Setting SynchronizationAgentProcessSecurity is not required when the subscription is created by a member of the sysadmin fixed server role, but we recommend it.
                        In this case, the agent will impersonate the SQL Server Agent account. For more information, see Replication Agent security model.

                        (Optional) A value of true (the default) for CreateSyncAgentByDefault to create an agent job that is used to synchronize the subscription.
                        If you specify false, the subscription can only be synchronized programmatically.

                        #>
                        if ($SubscriptionSqlCredential) {
                            $mergeSub.SubscriberSecurity.WindowsAuthentication = $false
                            $mergeSub.SubscriberSecurity.SqlStandardLogin = $SubscriptionSqlCredential.UserName
                            $mergeSub.SubscriberSecurity.SecureSqlStandardPassword = $SubscriptionSqlCredential.Password
                        }

                        $mergeSub.Create()
                    }

                } else {
                    Stop-Function -Message ("Publication {0} not found on {1}" -f $PublicationName, $instance) -Target $instance -Continue -FunctionName New-DbaReplSubscription
                }
            }
        } catch {
            Stop-Function -Message ("Unable to create subscription - {0}" -f $_) -ErrorRecord $_ -Target $instance -Continue -FunctionName New-DbaReplSubscription
        }
        #TODO: call Get-DbaReplSubscription when it's done
    }
} $SqlInstance $SqlCredential $Database $SubscriberSqlInstance $SubscriberSqlCredential $SubscriptionDatabase $PublicationName $SubscriptionSqlCredential $Type $EnableException $__realCmdlet @__commonParameters 3>&1 2>&1
""";
}
