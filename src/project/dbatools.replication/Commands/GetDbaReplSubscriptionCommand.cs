#nullable enable

using System;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves SQL Server replication subscription details for publications across instances.
/// Port of public/Get-DbaReplSubscription.ps1. The whole process body rides ONE VERBATIM module
/// hop per pipeline record: the per-instance foreach, the Connect-DbaInstance / Get-DbaReplPublication
/// calls (still module-scope PowerShell), the SMO Subscriptions enumeration with the identity
/// NoteProperty decoration and Select-DefaultView, and the distribution-database pull-subscription
/// fallback (ReplicationServer publisher/distributor guard, Invoke-DbaQuery against the distribution
/// db, pub-id/key dedup). The source is [CmdletBinding()] with no ShouldProcess, so no $__realCmdlet
/// carrier; in-hop Stop-Function/Write-Message carry -FunctionName and read $EnableException from the
/// hop param scope; merged-back warning/verbose/error records re-emit through the host cmdlet's own
/// streams. No cross-record state (each SqlInstance record is self-contained). Surface pinned by
/// migration/baselines/Get-DbaReplSubscription.json.
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaReplSubscription")]
public sealed class GetDbaReplSubscriptionCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>Specifies which publication databases to include when retrieving subscriptions.</summary>
    [Parameter(Position = 2)]
    public object[]? Database { get; set; }

    /// <summary>Filters results to subscriptions from specific publications by name.</summary>
    [Parameter(Position = 3)]
    public string[]? PublicationName { get; set; }

    /// <summary>Filters results to subscriptions delivered to specific subscriber instances.</summary>
    [Parameter(Position = 4)]
    public DbaInstanceParameter[]? SubscriberName { get; set; }

    /// <summary>Filters results to subscriptions delivered to specific databases on subscribers.</summary>
    [Parameter(Position = 5)]
    public object[]? SubscriptionDatabase { get; set; }

    /// <summary>Filters results to subscriptions of a specific delivery method (Push or Pull).</summary>
    [Parameter(Position = 6)]
    [Alias("PublicationType")]
    [ValidateSet("Push", "Pull")]
    public object[]? Type { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
        NestedCommand.InvokeScopedStreaming(this, item => WriteObject(item), BodyScript,
            SqlInstance, SqlCredential, Database, PublicationName, SubscriberName, SubscriptionDatabase, Type,
            EnableException.ToBool(), NestedCommand.BoundCommonParameter(this, "Verbose"), NestedCommand.BoundCommonParameter(this, "Debug"));
    }

    // The whole process body VERBATIM in the dbatools module scope: the per-instance foreach, the
    // still-PS Connect-DbaInstance / Get-DbaReplPublication calls, the SMO subscription enumeration
    // and decoration, and the distribution-database pull-subscription fallback. Stop-Function and
    // Write-Message carry -FunctionName.
    private const string BodyScript = """
param($SqlInstance, $SqlCredential, $Database, $PublicationName, $SubscriberName, $SubscriptionDatabase, $Type, $EnableException, $__boundVerbose, $__boundDebug)
$__commonParameters = @{}
if ($null -ne $__boundVerbose) { $__commonParameters.Verbose = [bool]$__boundVerbose }
if ($null -ne $__boundDebug) { $__commonParameters.Debug = [bool]$__boundDebug }
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    [CmdletBinding()]
    param([Dataplat.Dbatools.Parameter.DbaInstanceParameter[]]$SqlInstance, $SqlCredential, $Database, $PublicationName, $SubscriberName, $SubscriptionDatabase, $Type, $EnableException)

    if (Test-FunctionInterrupt) { return }

    foreach ($instance in $SqlInstance) {
        try {
            $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential
        } catch {
            Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue -FunctionName Get-DbaReplSubscription
        }

        try {
            $publications = Get-DbaReplPublication -SqlInstance $server -EnableException:$EnableException

            if ($Database) {
                $publications = $publications | Where-Object DatabaseName -in $Database
            }

            if ($PublicationName) {
                $publications = $publications | Where-Object Name -in $PublicationName
            }

        } catch {
            Stop-Function -Message "Error occurred while getting publications from $instance" -ErrorRecord $_ -Target $instance -Continue -FunctionName Get-DbaReplSubscription
        }

        # Track subscriptions already emitted to avoid duplicates from the distribution DB check
        $foundSubscriptionKeys = @{ }

        try {
            foreach ($subs in $publications.Subscriptions) {
                Write-Message -Level Verbose -Message ('Get subscriptions for {0}' -f $sub.PublicationName) -FunctionName Get-DbaReplSubscription -ModuleName "dbatools"

                if ($SubscriberName) {
                    $subs = $subs | Where-Object SubscriberName -eq $SubscriberName
                }

                if ($SubscriptionDatabase) {
                    $subs = $subs | Where-Object SubscriptionDBName -eq $SubscriptionDatabase
                }

                if ($Type) {
                    $subs = $subs | Where-Object SubscriptionType -eq $Type
                }

                foreach ($sub in $subs) {
                    $subKey = "$($sub.SubscriberName)|$($sub.SubscriptionDBName)|$($sub.PublicationName)|$($sub.DatabaseName)"
                    $foundSubscriptionKeys[$subKey] = $true

                    Add-Member -Force -InputObject $sub -MemberType NoteProperty -Name ComputerName -Value $server.ComputerName
                    Add-Member -Force -InputObject $sub -MemberType NoteProperty -Name InstanceName -Value $server.ServiceName
                    Add-Member -Force -InputObject $sub -MemberType NoteProperty -Name SqlInstance -Value $server.DomainInstanceName

                    Select-DefaultView -InputObject $sub -Property ComputerName, InstanceName, SqlInstance, DatabaseName, PublicationName, Name, SubscriberName, SubscriptionDBName, SubscriptionType
                }
            }
        } catch {
            Stop-Function -Message "Error occurred while getting subscriptions from $instance" -ErrorRecord $_ -Target $instance -Continue -FunctionName Get-DbaReplSubscription
        }

        # Also check distribution database for pull subscriptions that may be missing from publisher's syssubscriptions.
        # This handles cases where pull subscriptions were created outside the normal process and only exist in distribution.dbo.MSsubscriptions.
        if (-not $Type -or "Pull" -in $Type) {
            try {
                $replServer = New-Object Microsoft.SqlServer.Replication.ReplicationServer
                $replServer.ConnectionContext = $server.ConnectionContext

                if ($replServer.IsPublisher -and $replServer.DistributorInstalled -and $replServer.DistributorAvailable) {
                    $distributorName = $replServer.DistributionServer
                    $distributionDbName = $replServer.DistributionDatabase

                    try {
                        # Reuse the existing connection if the distributor is the same server
                        if ($distributorName -eq $server.ComputerName -or $distributorName -eq $server.DomainInstanceName) {
                            $distributorServer = $server
                        } else {
                            $distributorServer = Connect-DbaInstance -SqlInstance $distributorName -SqlCredential $SqlCredential
                        }

                        $distQuery = "
                            SELECT DISTINCT
                                a.subscriber_name AS SubscriberName,
                                a.subscriber_db   AS SubscriptionDBName,
                                p.publisher_db    AS DatabaseName,
                                p.publication     AS PublicationName,
                                p.publication_id  AS PublicationId
                            FROM MSdistribution_agents a
                            INNER JOIN MSsubscriptions s ON s.agent_id = a.id AND s.subscription_type = 1
                            INNER JOIN MSpublications p ON p.publication_id = s.publication_id
                        "

                        $splatDistQuery = @{
                            SqlInstance = $distributorServer
                            Database    = $distributionDbName
                            Query       = $distQuery
                        }
                        $distPullSubs = Invoke-DbaQuery @splatDistQuery

                        # Prefer publication IDs when available so publications with the same name on other publishers
                        # sharing the same distributor are not returned for this publisher.
                        $publicationIds = @{ }
                        $publicationKeys = @{ }
                        foreach ($pub in $publications) {
                            if ($null -ne $pub.PubId) {
                                $publicationIds["$($pub.PubId)"] = $true
                            }

                            $pubKey = "$($pub.DatabaseName)|$($pub.Name)"
                            $publicationKeys[$pubKey] = $true
                        }

                        $usePublicationIdLookup = $publicationIds.Count -eq @($publications).Count -and $publicationIds.Count -gt 0

                        # Convert SubscriberName filter to strings for comparison
                        $subscriberNameStrings = @()
                        if ($SubscriberName) {
                            $subscriberNameStrings = $SubscriberName | ForEach-Object { $_.ToString() }
                        }

                        foreach ($distSub in $distPullSubs) {
                            # Only process subscriptions for publications we already queried
                            if ($usePublicationIdLookup) {
                                if (-not $publicationIds.ContainsKey("$($distSub.PublicationId)")) { continue }
                            } else {
                                $pubKey = "$($distSub.DatabaseName)|$($distSub.PublicationName)"
                                if (-not $publicationKeys.ContainsKey($pubKey)) { continue }
                            }

                            # Apply subscriber name filter
                            if ($subscriberNameStrings -and $distSub.SubscriberName -notin $subscriberNameStrings) { continue }

                            # Apply subscription database filter
                            if ($SubscriptionDatabase -and $distSub.SubscriptionDBName -notin $SubscriptionDatabase) { continue }

                            # Skip subscriptions already returned via SMO
                            $subKey = "$($distSub.SubscriberName)|$($distSub.SubscriptionDBName)|$($distSub.PublicationName)|$($distSub.DatabaseName)"
                            if ($foundSubscriptionKeys.ContainsKey($subKey)) { continue }

                            # Emit subscriptions found only in the distribution database
                            $subObj = [PSCustomObject]@{
                                ComputerName       = $server.ComputerName
                                InstanceName       = $server.ServiceName
                                SqlInstance        = $server.DomainInstanceName
                                DatabaseName       = $distSub.DatabaseName
                                PublicationName    = $distSub.PublicationName
                                Name               = "$($distSub.PublicationName)-$($distSub.SubscriberName)-$($distSub.SubscriptionDBName)"
                                SubscriberName     = $distSub.SubscriberName
                                SubscriptionDBName = $distSub.SubscriptionDBName
                                SubscriptionType   = "Pull"
                            }

                            Select-DefaultView -InputObject $subObj -Property ComputerName, InstanceName, SqlInstance, DatabaseName, PublicationName, Name, SubscriberName, SubscriptionDBName, SubscriptionType
                        }
                    } catch {
                        Write-Message -Level Warning -Message "Could not query distribution database on $distributorName for additional pull subscriptions from $instance" -FunctionName Get-DbaReplSubscription -ModuleName "dbatools"
                    }
                }
            } catch {
                Write-Message -Level Verbose -Message "Unable to check distribution database for additional pull subscriptions from $instance" -FunctionName Get-DbaReplSubscription -ModuleName "dbatools"
            }
        }
    }
} $SqlInstance $SqlCredential $Database $PublicationName $SubscriberName $SubscriptionDatabase $Type $EnableException @__commonParameters 3>&1 2>&1
""";
}
