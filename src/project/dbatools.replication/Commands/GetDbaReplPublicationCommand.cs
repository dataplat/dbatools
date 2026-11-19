#nullable enable

using System;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;
using Microsoft.SqlServer.Replication;
// The SMO Database type collides with a `Database` namespace (and with this command's -Database
// parameter); alias it so `SmoDatabase` unambiguously means the SMO object.
using SmoDatabase = Microsoft.SqlServer.Management.Smo.Database;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves replication publications (transactional, merge, and snapshot) from SQL Server
/// instances. Pure-C# port of public/Get-DbaReplPublication.ps1; its sole module-scoped helper,
/// private/functions/Connect-ReplicationDB.ps1, is provided by Commands/Support/ReplicationDb.cs
/// (built for exactly this command). Surface pinned by migration/baselines/Get-DbaReplPublication.json.
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaReplPublication")]
[OutputType(typeof(Publication))]
public sealed class GetDbaReplPublicationCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>Databases to examine for replication publications (default: all published, non-system).</summary>
    [Parameter(Position = 2)]
    public object[]? Database { get; set; }

    /// <summary>Filters results to publications with the specified name.</summary>
    [Parameter(Position = 3)]
    public string? Name { get; set; }

    /// <summary>Limits results to specific publication types: Transactional, Merge, or Snapshot.</summary>
    [Parameter(Position = 4)]
    [Alias("PublicationType")]
    [ValidateSet("Transactional", "Merge", "Snapshot")]
    public object[]? Type { get; set; }

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            // PS: try { Connect-DbaInstance -MinimumVersion 9 } catch { Stop-Function "Failure" -Category ConnectionError -Continue }
            Server server;
            try
            {
                SmoConnectionRequest request = new();
                request.Instance = instance;
                request.SqlCredential = SqlCredential;
                request.MinimumVersion = 9;
                server = ConnectionService.GetServer(request);
                SetActiveConnection(server.ConnectionContext);
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception ex)
            {
                StopFunction("Failure", target: instance, errorRecord: new ErrorRecord(ex, "dbatools_Get-DbaReplPublication", ErrorCategory.ConnectionError, instance), category: ErrorCategory.ConnectionError, continueLoop: true);
                continue;
            }

            // PS: $databases = $server.Databases | Where { $_.IsAccessible -and -not $_.IsSystemObject }
            //     if ($Database) { $databases = $databases | Where Name -In $Database }
            List<SmoDatabase> databases = new();
            try
            {
                foreach (SmoDatabase db in server.Databases)
                {
                    if (db.IsAccessible && !db.IsSystemObject)
                    {
                        databases.Add(db);
                    }
                }

                if (Database != null && Database.Length > 0)
                {
                    List<SmoDatabase> selected = new();
                    foreach (SmoDatabase db in databases)
                    {
                        foreach (object candidate in Database)
                        {
                            // -In is case-insensitive; a non-string element coerces via ToString (PS -eq semantics)
                            if (string.Equals(db.Name, candidate?.ToString(), StringComparison.InvariantCultureIgnoreCase))
                            {
                                selected.Add(db);
                                break;
                            }
                        }
                    }
                    databases = selected;
                }
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception ex)
            {
                StopFunction("Unable to get databases for", target: server, errorRecord: new ErrorRecord(ex, "dbatools_Get-DbaReplPublication", ErrorCategory.NotSpecified, server), continueLoop: true);
                continue;
            }

            // The whole database loop rides ONE try, matching the source: a failure enumerating any
            // database's publications aborts this instance and continues to the next (Stop-Function -Continue).
            try
            {
                foreach (SmoDatabase db in databases)
                {
                    // test if the database published
                    ReplicationOptions options = db.ReplicationOptions;
                    if ((options & ReplicationOptions.Published) != ReplicationOptions.Published &&
                        (options & ReplicationOptions.MergePublished) != ReplicationOptions.MergePublished)
                    {
                        // The database is not published
                        WriteMessage(MessageLevel.Verbose, $"Skipping {db.Name}. Database is not published.");
                        continue;
                    }

                    // PS: $repDB = Connect-ReplicationDB -Server $server -Database $db -EnableException:$EnableException
                    // The helper's [switch]$EnableException is declared but never used (ReplicationDb.cs header),
                    // so the port passes no equivalent; the verbose "failed to load properties" message rides the callback.
                    ReplicationDatabase repDB = ReplicationDb.Connect(server, db, (level, message) => WriteMessage(level, message));

                    // PS: $pubTypes = $repDB.TransPublications + $repDB.MergePublications (trans first, preserving order)
                    List<Publication> pubTypes = new();
                    foreach (TransPublication pub in repDB.TransPublications)
                    {
                        pubTypes.Add(pub);
                    }
                    foreach (MergePublication pub in repDB.MergePublications)
                    {
                        pubTypes.Add(pub);
                    }

                    if (Type != null && Type.Length > 0)
                    {
                        List<Publication> selected = new();
                        foreach (Publication pub in pubTypes)
                        {
                            foreach (object wanted in Type)
                            {
                                if (string.Equals(pub.Type.ToString(), wanted?.ToString(), StringComparison.InvariantCultureIgnoreCase))
                                {
                                    selected.Add(pub);
                                    break;
                                }
                            }
                        }
                        pubTypes = selected;
                    }

                    if (!string.IsNullOrEmpty(Name))
                    {
                        // PS: Where Name -in $Name; $Name is scalar so -in reduces to case-insensitive -eq
                        List<Publication> selected = new();
                        foreach (Publication pub in pubTypes)
                        {
                            if (string.Equals(pub.Name, Name, StringComparison.InvariantCultureIgnoreCase))
                            {
                                selected.Add(pub);
                            }
                        }
                        pubTypes = selected;
                    }

                    foreach (Publication pub in pubTypes)
                    {
                        object? articles;
                        object? subscriptions;
                        if (string.Equals(pub.Type.ToString(), "Merge", StringComparison.InvariantCultureIgnoreCase))
                        {
                            // PS reads $pub.MergeArticles/$pub.MergeSubscriptions; non-merge -> $null (non-strict)
                            articles = (pub as MergePublication)?.MergeArticles;
                            subscriptions = (pub as MergePublication)?.MergeSubscriptions;
                        }
                        else
                        {
                            articles = (pub as TransPublication)?.TransArticles;
                            subscriptions = (pub as TransPublication)?.TransSubscriptions;
                        }

                        // PS: Add-Member -Force NoteProperty ... then Select-DefaultView. $server.ComputerName is
                        // the decorated ETS value (GetComputerName); SQLInstance carries the whole server object.
                        PSObject wrapped = PSObject.AsPSObject(pub);
                        ReplaceNoteProperty(wrapped, "ComputerName", SmoServerExtensions.GetComputerName(server));
                        ReplaceNoteProperty(wrapped, "InstanceName", server.ServiceName);
                        ReplaceNoteProperty(wrapped, "SQLInstance", server);
                        ReplaceNoteProperty(wrapped, "Articles", articles);
                        ReplaceNoteProperty(wrapped, "Subscriptions", subscriptions);
                        OutputHelper.SetDefaultDisplayPropertySet(wrapped,
                            "ComputerName", "InstanceName", "SQLInstance", "DatabaseName", "Name", "Type", "Articles", "Subscriptions");
                        WriteObject(wrapped);
                    }
                }
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception ex)
            {
                StopFunction("Unable to get publications from ", target: server, errorRecord: new ErrorRecord(ex, "dbatools_Get-DbaReplPublication", ErrorCategory.NotSpecified, server), continueLoop: true);
                continue;
            }
        }
    }

    private static void ReplaceNoteProperty(PSObject wrapped, string name, object? value)
    {
        PSPropertyInfo? existing = wrapped.Properties[name];
        if (existing is PSNoteProperty)
        {
            wrapped.Properties.Remove(name);
        }
        wrapped.Properties.Add(new PSNoteProperty(name, value));
    }
}
