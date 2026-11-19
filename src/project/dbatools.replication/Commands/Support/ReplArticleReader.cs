#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Common;
using Microsoft.SqlServer.Management.Smo;
using Microsoft.SqlServer.Replication;
using SmoDatabase = Microsoft.SqlServer.Management.Smo.Database;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// The cmdlet a Get-DbaReplArticle read runs in: Get-DbaReplArticle itself, or a command whose pin calls it nested
/// with -EnableException:$EnableException (Get-DbaReplArticleColumn). Every message and stop keeps Get-DbaReplArticle's
/// attribution, as the nested function's own Write-Message and Stop-Function do.
/// </summary>
internal interface IReplArticleHost
{
    /// <summary>The -SqlCredential the read connects with.</summary>
    PSCredential? Credential { get; }

    /// <summary>Whether -EnableException is set; the nested call passes the caller's own value.</summary>
    bool EnableExceptionSet { get; }

    /// <summary>Write-Message under the named function.</summary>
    void Message(string functionName, MessageLevel level, string message);

    /// <summary>Stop-Function -Continue under the named function: a warning, or a terminating throw under -EnableException.</summary>
    void StopContinue(string functionName, string message, object? target, ErrorRecord record, ErrorCategory category, bool overrideExceptionMessage);

    /// <summary>A nested Stop-Function under -EnableException whose throw a catch of the read receives.</summary>
    ErrorRecord CaughtNestedStop(string functionName, string message, object? target, ErrorRecord record);

    /// <summary>A nested Stop-Function -Continue without -EnableException.</summary>
    void WarnNestedStop(string functionName, string message, object? target, ErrorRecord record);

    /// <summary>Registers the connection in use so Ctrl-C can cancel it.</summary>
    void Connected(ServerConnection connection);

    /// <summary>A connection target's text with any password masked.</summary>
    string MaskTarget(object target);
}

/// <summary>
/// Get-DbaReplArticle's process block, shared by the command and by Get-DbaReplArticleColumn, whose pin calls it
/// nested. Each article goes to the sink as the pin emits it: decorated with ComputerName, InstanceName and SqlInstance
/// and its ten-property default view.
/// </summary>
internal static class ReplArticleReader
{
    internal const string ArticleCommand = "Get-DbaReplArticle";
    private const string PublicationCommand = "Get-DbaReplPublication";
    private const string ConnectCommand = "Connect-DbaInstance";

    internal static void Read(IReplArticleHost host, DbaInstanceParameter[] instances, object[]? databaseFilter,
        object[]? publicationFilter, string[]? schemaFilter, string[]? nameFilter, Action<PSObject> emit)
    {
        foreach (DbaInstanceParameter instance in instances)
        {
            // PS: try { $server = Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential }
            //     catch { Stop-Function -Message "Error occurred while establishing connection to $instance" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue }
            // Upstream correction azure-unsupported: Azure SQL Database can only be a push subscriber, never a publisher, so the
            // connection refuses it as Connect-DbaInstance -AzureUnsupported does, before any database work.
            Server? server = Connect(host, instance,
                String.Format(CultureInfo.InvariantCulture, "Error occurred while establishing connection to {0}", instance));
            if (server is null)
                continue;

            // PS: $databases = $server.Databases | Where-Object IsAccessible -eq $true
            //     if ($Database) { $databases = $databases | Where-Object Name -in $Database }
            List<SmoDatabase> databases = new();
            try
            {
                foreach (SmoDatabase db in server.Databases)
                {
                    if (db.IsAccessible && (!PsOps.IsTrue(databaseFilter) || PsOps.In(db.Name, databaseFilter)))
                        databases.Add(db);
                }
            }
            catch (Exception failure) when (failure is not PipelineStoppedException)
            {
                host.StopContinue(ArticleCommand, String.Format(CultureInfo.InvariantCulture, "Error occurred while getting databases from {0}", instance),
                    instance, CaughtRecord(failure), ErrorCategory.NotSpecified, false);
                continue;
            }

            // The pin wraps the whole database loop in one try: a failure in any database ends this instance.
            try
            {
                foreach (SmoDatabase db in databases)
                {
                    host.Message(ArticleCommand, MessageLevel.Verbose, String.Format(CultureInfo.InvariantCulture, "Working on {0}", db.Name));

                    // PS: $publications = Get-DbaReplPublication -SqlInstance $server -Database $db.Name -EnableException:$EnableException
                    List<KeyValuePair<Publication, IEnumerable>> publications = ReadPublications(host, server, db.Name);

                    // PS: if ($Publication) { $publications = $publications | Where-Object Name -in $Publication }
                    // PS: $articles = $publications.Articles - member enumeration flattens every publication's
                    // article collection, in publication order.
                    List<Article> articles = new();
                    foreach (KeyValuePair<Publication, IEnumerable> publication in publications)
                    {
                        if (PsOps.IsTrue(publicationFilter) && !PsOps.In(publication.Key.Name, publicationFilter))
                            continue;
                        foreach (object? item in publication.Value)
                        {
                            if (item is Article article)
                                articles.Add(article);
                        }
                    }

                    // PS: if ($Schema) { $articles = $articles | Where-Object SourceObjectOwner -in $Schema }
                    if (PsOps.IsTrue(schemaFilter))
                        articles = articles.FindAll(article => PsOps.In(article.SourceObjectOwner, schemaFilter));
                    // PS: if ($Name) { $articles = $articles | Where-Object Name -in $Name }
                    if (PsOps.IsTrue(nameFilter))
                        articles = articles.FindAll(article => PsOps.In(article.Name, nameFilter));

                    foreach (Article article in articles)
                    {
                        // PS: Add-Member -Force ComputerName, InstanceName, SqlInstance (the server object itself),
                        //     then Select-DefaultView with the ten listed properties.
                        PSObject output = PSObject.AsPSObject(article);
                        ReplaceNote(output, "ComputerName", SmoServerExtensions.GetComputerName(server));
                        ReplaceNote(output, "InstanceName", server.ServiceName);
                        ReplaceNote(output, "SqlInstance", server);
                        OutputHelper.SetDefaultDisplayPropertySet(output, "ComputerName", "InstanceName", "SqlInstance", "DatabaseName",
                            "PublicationName", "Name", "Type", "VerticalPartition", "SourceObjectOwner", "SourceObjectName");
                        emit(output);
                    }
                }
            }
            catch (Exception failure) when (failure is not PipelineStoppedException)
            {
                // A nested Get-DbaReplPublication stop under -EnableException arrives here as the record it threw.
                ErrorRecord record = failure is NestedStopException nested ? nested.Record : CaughtRecord(failure);
                host.StopContinue(ArticleCommand, String.Format(CultureInfo.InvariantCulture, "Error occurred while getting articles from {0}", instance),
                    instance, record, ErrorCategory.NotSpecified, false);
                continue;
            }
        }
    }

    // PS: Connect-DbaInstance -SqlInstance $instance -SqlCredential $SqlCredential inside Get-DbaReplArticle's try, with its
    // catch's Stop-Function -Continue -Category ConnectionError. A failed connection shows as one line naming the server
    // (harness-edits.md, "Script-scope preferences and the one-line connect warning", point 5); a refusal keeps its text.
    private static Server? Connect(IReplArticleHost host, DbaInstanceParameter instance, string failureMessage)
    {
        host.Message(ConnectCommand, MessageLevel.Debug, "Starting process block");
        try
        {
            SmoConnectionRequest request = new()
            {
                Instance = instance,
                SqlCredential = host.Credential,
                AzureUnsupported = true,
                BoundParameters = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "SqlInstance", "SqlCredential" },
                MessageCallback = (level, message) => host.Message(ConnectCommand, level, message)
            };
            Server server = ConnectionService.GetServer(request);
            host.Connected(server.ConnectionContext);
            host.Message(ConnectCommand, MessageLevel.Debug, "We are finished with this instance");
            return server;
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            ErrorRecord record = new(failure, "dbatools_" + ArticleCommand, ErrorCategory.ConnectionError, instance);
            if (failure is ConnectionResolutionException resolution && resolution.Kind == ConnectionResolutionFailure.ConnectFailure)
            {
                string line = String.Format(CultureInfo.InvariantCulture, "{0} | Error connecting to [{1}]: {2}", failureMessage,
                    host.MaskTarget(instance), MessageService.GetErrorMessage(record));
                host.StopContinue(ArticleCommand, line, instance, record, ErrorCategory.ConnectionError, true);
                return null;
            }
            host.StopContinue(ArticleCommand, failureMessage, instance, record, ErrorCategory.ConnectionError, false);
            return null;
        }
    }

    // The pinned nested call Get-DbaReplPublication -SqlInstance $server -Database $db.Name, reduced to what this command
    // reads from it: each publication with its Articles collection. Its Connect-DbaInstance -SqlInstance $server -MinimumVersion 9
    // hands back the already connected server. The publications it emitted before a failure stay in the result, as the
    // pinned assignment keeps every object the nested function wrote before its Stop-Function -Continue.
    private static List<KeyValuePair<Publication, IEnumerable>> ReadPublications(IReplArticleHost host, Server server, string databaseName)
    {
        List<KeyValuePair<Publication, IEnumerable>> emitted = new();
        object[] wanted = new object[] { databaseName };

        // PS: $databases = $server.Databases | Where-Object { $_.IsAccessible -eq $true -and (-not $_.IsSystemObject) }
        //     if ($Database) { $databases = $databases | Where-Object Name -In $Database }
        // -In compares without case, as the pin does, so the publications of every name matching the outer database are read.
        List<SmoDatabase> databases = new();
        try
        {
            foreach (SmoDatabase db in server.Databases)
            {
                if (db.IsAccessible && !db.IsSystemObject && PsOps.In(db.Name, wanted))
                    databases.Add(db);
            }
        }
        catch (Exception failure) when (failure is not PipelineStoppedException and not NestedStopException)
        {
            // PS: Stop-Function -Message "Unable to get databases for" -ErrorRecord $_ -Target $server -Continue
            NestedStop(host, "Unable to get databases for", server, CaughtRecord(failure));
            return emitted;
        }

        try
        {
            foreach (SmoDatabase db in databases)
            {
                // PS: test if the database published (Published or MergePublished)
                ReplicationOptions options = Get(() => db.ReplicationOptions, "ReplicationOptions");
                if ((options & ReplicationOptions.Published) != ReplicationOptions.Published
                    && (options & ReplicationOptions.MergePublished) != ReplicationOptions.MergePublished)
                {
                    host.Message(PublicationCommand, MessageLevel.Verbose,
                        String.Format(CultureInfo.InvariantCulture, "Skipping {0}. Database is not published.", db.Name));
                    continue;
                }

                // PS: $repDB = Connect-ReplicationDB -Server $server -Database $db -EnableException:$EnableException
                ReplicationDatabase replicationDatabase;
                try
                {
                    replicationDatabase = ReplicationDb.Connect(server, db,
                        (level, message) => host.Message("Connect-ReplicationDB", level, message ?? String.Empty));
                }
                catch (Exception failure) when (failure is not PipelineStoppedException)
                {
                    throw new MethodInvocationException(String.Format(CultureInfo.InvariantCulture,
                        "Exception calling \"LoadProperties\" with \"0\" argument(s): \"{0}\"", failure.Message), failure);
                }

                // PS: $pubTypes = $repDB.TransPublications + $repDB.MergePublications
                List<Publication> publications = new();
                foreach (object? item in Get(() => replicationDatabase.TransPublications, "TransPublications"))
                {
                    if (item is Publication publication)
                        publications.Add(publication);
                }
                foreach (object? item in Get(() => replicationDatabase.MergePublications, "MergePublications"))
                {
                    if (item is Publication publication)
                        publications.Add(publication);
                }

                foreach (Publication publication in publications)
                {
                    // PS: if ($pub.Type -eq 'Merge') { $articles = $pub.MergeArticles } else { $articles = $pub.TransArticles }
                    // The pin reads the collection here, before it emits the publication with it as its Articles note.
                    emitted.Add(new KeyValuePair<Publication, IEnumerable>(publication, ArticlesOf(publication)));
                }
            }
        }
        catch (Exception failure) when (failure is not PipelineStoppedException and not NestedStopException)
        {
            // PS: Stop-Function -Message "Unable to get publications from " -ErrorRecord $_ -Target $server -Continue
            NestedStop(host, "Unable to get publications from ", server, CaughtRecord(failure));
        }
        return emitted;
    }

    // The article collection the nested command attached to the publication as its Articles note.
    private static IEnumerable ArticlesOf(Publication publication)
    {
        if (Get(() => publication.Type, "Type") == PublicationType.Merge)
            return publication is MergePublication merge ? Get(() => merge.MergeArticles, "MergeArticles") : Array.Empty<object>();
        return publication is TransPublication trans ? Get(() => trans.TransArticles, "TransArticles") : Array.Empty<object>();
    }

    // Stop-Function -Continue inside the nested Get-DbaReplPublication, which the pin calls with -EnableException:$EnableException.
    // Without it the nested command warns under its own name and returns what it emitted; with it the nested throw reaches
    // the catch around the database loop.
    private static void NestedStop(IReplArticleHost host, string message, Server server, ErrorRecord record)
    {
        if (host.EnableExceptionSet)
            throw new NestedStopException(host.CaughtNestedStop(PublicationCommand, message, server, record));
        host.WarnNestedStop(PublicationCommand, message, server, record);
    }

    /// <summary>
    /// A property read the pin performs through the PowerShell adapter: a failing getter reaches its catch as the
    /// adapter's GetValueInvocationException.
    /// </summary>
    internal static T Get<T>(Func<T> getter, string propertyName)
    {
        try
        {
            return getter();
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            throw new GetValueInvocationException(String.Format(CultureInfo.InvariantCulture,
                "Exception getting \"{0}\": \"{1}\"", propertyName, failure.Message), failure);
        }
    }

    /// <summary>
    /// The record PowerShell hands a catch block as $_ for a .NET failure: an adapter getter failure carries
    /// CatchFromBaseAdapterGetValue, a method failure the inner exception's type name.
    /// </summary>
    internal static ErrorRecord CaughtRecord(Exception failure)
    {
        if (failure is GetValueInvocationException)
            return new ErrorRecord(failure, "CatchFromBaseAdapterGetValue", ErrorCategory.NotSpecified, null);
        if (failure is MethodInvocationException call && call.InnerException is not null)
            return new ErrorRecord(call, call.InnerException.GetType().Name, ErrorCategory.NotSpecified, null);
        return new ErrorRecord(failure, failure.GetType().Name, ErrorCategory.NotSpecified, null);
    }

    /// <summary>Add-Member -Force -MemberType NoteProperty: an existing note of that name is replaced.</summary>
    internal static void ReplaceNote(PSObject output, string name, object? value)
    {
        if (output.Properties[name] is PSNoteProperty)
            output.Properties.Remove(name);
        output.Properties.Add(new PSNoteProperty(name, value));
    }

    // Carries the record a nested Stop-Function threw under -EnableException to the catch that receives it as $_.
    private sealed class NestedStopException : Exception
    {
        internal NestedStopException(ErrorRecord record)
            : base(record.Exception.Message, record.Exception)
        {
            Record = record;
        }

        internal ErrorRecord Record { get; }
    }
}

/// <summary>
/// The base of the commands that run a Get-DbaReplArticle read: each host call goes to the cmdlet's own messaging and
/// Stop-Function primitives under the attribution the reader names.
/// </summary>
public abstract class ReplArticleHostCmdlet : DbaInstanceCmdlet, IReplArticleHost
{
    PSCredential? IReplArticleHost.Credential => SqlCredential;

    bool IReplArticleHost.EnableExceptionSet => EnableException.ToBool();

    void IReplArticleHost.Message(string functionName, MessageLevel level, string message)
    {
        WriteAttributedMessage(functionName, level, message);
    }

    void IReplArticleHost.StopContinue(string functionName, string message, object? target, ErrorRecord record, ErrorCategory category,
        bool overrideExceptionMessage)
    {
        // Get-DbaReplArticle's own Stop-Function -Continue. Nested in Get-DbaReplArticleColumn it warns under that name, and
        // under -EnableException its throw is not caught there either, so it ends the calling command.
        StopAttributedFunction(functionName, message, target: target, errorRecord: record, category: category, continueLoop: true,
            overrideExceptionMessage: overrideExceptionMessage);
    }

    ErrorRecord IReplArticleHost.CaughtNestedStop(string functionName, string message, object? target, ErrorRecord record)
    {
        return CaughtNestedStopFunction(functionName, message, target: target, errorRecord: record);
    }

    void IReplArticleHost.WarnNestedStop(string functionName, string message, object? target, ErrorRecord record)
    {
        WarnNestedStopFunction(functionName, message, target: target, errorRecord: record);
    }

    void IReplArticleHost.Connected(ServerConnection connection)
    {
        SetActiveConnection(connection);
    }

    string IReplArticleHost.MaskTarget(object target)
    {
        return MaskedTargetText(target);
    }
}
