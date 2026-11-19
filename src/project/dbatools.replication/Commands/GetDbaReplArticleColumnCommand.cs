#nullable enable

using System;
using System.Collections.Generic;
using System.Data;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.Data.SqlClient;
using Microsoft.SqlServer.Management.Common;
using Microsoft.SqlServer.Management.Smo;
using MergeArticle = Microsoft.SqlServer.Replication.MergeArticle;
using RmoArticle = Microsoft.SqlServer.Replication.Article;
using TransArticle = Microsoft.SqlServer.Replication.TransArticle;
// The SMO Database type collides with this command's -Database parameter.
using SmoDatabase = Microsoft.SqlServer.Management.Smo.Database;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves column-level replication configuration details for SQL Server publication articles.
/// </summary>
/// <para>
/// Returns detailed information about which columns are included in replication articles, helping DBAs audit replication configurations and troubleshoot column-specific replication issues. This is particularly useful when working with vertical partitioning scenarios where only specific columns from source tables are replicated to subscribers, or when investigating why certain columns aren't appearing in replicated data.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaReplArticleColumn -SqlInstance sqlserver2019
/// </code>
/// <para>
/// Retrieve information of all replicated columns in any publications on server sqlserver2019.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaReplArticleColumn -SqlInstance sqlserver2019 -Database pubs
/// </code>
/// <para>
/// Retrieve information of all replicated columns in any publications from the pubs database on server sqlserver2019.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaReplArticleColumn -SqlInstance sqlserver2019 -Publication test
/// </code>
/// <para>
/// Retrieve information of all replicated columns in the test publication on server sqlserver2019.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaReplArticleColumn -SqlInstance sqlserver2019 -Database pubs -Publication PubName -Article sales
/// </code>
/// <para>
/// Retrieve information of 'sales' article from 'PubName' on 'pubs' database for server sqlserver2019.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaReplArticleColumn -SqlInstance sqlserver2019 -Column state
/// </code>
/// <para>
/// Retrieve information for the state column in any publication from any database on server sqlserver2019.
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: repl, Replication
/// Author: Cláudio Silva (@claudioessilva), claudioessilva.eu
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2023 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Get-DbaReplArticleColumn" />
[Cmdlet(VerbsCommon.Get, "DbaReplArticleColumn")]
public sealed class GetDbaReplArticleColumnCommand : ReplArticleHostCmdlet
{
    private const string QueryRunner = "Invoke-DbaQuery";

    // The pinned vertical-partition query. Correction vp-publication-scope: article names are unique only within a
    // publication, so the subquery also matches the article's publication.
    private const string PartitionQuery = @"SELECT c.name as ColumnName
FROM sysarticlecolumns ac
INNER JOIN sys.columns c ON ac.colid = c.column_id
INNER JOIN sys.tables t ON c.object_id = t.object_id AND ac.artid = (
    SELECT a.artid FROM sysarticles a INNER JOIN syspublications p ON a.pubid = p.pubid
    WHERE a.name = @articleName AND p.name = @publicationName
)
WHERE t.name = @tableName
    AND SCHEMA_NAME(t.schema_id) = @schemaName
ORDER BY c.column_id";

    // Correction merge-partition: a merge article's columns are not in the transactional catalog; the publisher's
    // sp_helpmergearticlecolumn lists each column of the article with whether it is published.
    private const string MergePartitionQuery = "EXEC sys.sp_helpmergearticlecolumn @publication = @publicationName, @article = @articleName";

    // Correction source-columns: the source table's columns, read in the article's database.
    private const string SourceColumnQuery = @"SELECT c.name
FROM sys.tables t
INNER JOIN sys.columns c ON c.object_id = t.object_id
WHERE t.name = @tableName
    AND SCHEMA_NAME(t.schema_id) = @schemaName
ORDER BY c.column_id";

    /// <para>
    /// The target SQL Server instance or instances.
    /// </para>
    [Parameter(Position = 0, ValueFromPipeline = true)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <para>
    /// Login to the target instance using alternative credentials. Accepts PowerShell credentials (Get-Credential).
    /// </para>
    /// <para>
    /// Windows Authentication, SQL Server Authentication, Active Directory - Password, and Active Directory - Integrated are all supported.
    /// </para>
    /// <para>
    /// For MFA support, please use Connect-DbaInstance.
    /// </para>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <para>
    /// Filters results to specific database(s) containing publications. Accepts wildcards for pattern matching.
    /// Use this when you need to focus on replication columns from particular databases rather than scanning all databases on the instance.
    /// </para>
    [Parameter(Position = 2)]
    public object[]? Database { get; set; }

    /// <para>
    /// Filters results to specific publication(s) within the specified databases. Accepts wildcards for pattern matching.
    /// Use this when auditing column replication configuration for particular publications or troubleshooting column-level issues in specific publications.
    /// </para>
    [Parameter(Position = 3, ValueFromPipeline = true)]
    public object[]? Publication { get; set; }

    /// <para>
    /// Filters results to specific article(s) within the publications. Accepts wildcards for pattern matching.
    /// Use this when you need to examine column replication details for particular tables or views that are published as articles.
    /// </para>
    [Parameter(Position = 4)]
    public string[]? Article { get; set; }

    /// <para>
    /// Filters results to specific column name(s) across all matched articles. Case-sensitive exact match.
    /// Use this when investigating whether specific columns are included in replication or troubleshooting missing columns in subscriber databases.
    /// </para>
    [Parameter(Position = 5)]
    public string[]? Column { get; set; }

    protected override void ProcessRecord()
    {
        // PS: if (Test-FunctionInterrupt) { return }
        if (Interrupted)
            return;

        // PS: $articles = Get-DbaReplArticle -SqlInstance $SqlInstance -SqlCredential $SqlCredential -Database $Database
        //         -Publication $Publication -Name $Article -EnableException:$EnableException
        // The assignment collects every article before the loop starts; a nested stop under -EnableException is not caught
        // here, so it ends this command with nothing emitted for this record.
        List<PSObject> articles = new();
        if (SqlInstance is not null)
            ReplArticleReader.Read(this, SqlInstance, Database, Publication, null, Article, articles.Add);

        foreach (PSObject art in articles)
        {
            try
            {
                EmitColumns(art);
            }
            catch (Exception failure) when (failure is not PipelineStoppedException)
            {
                // PS: Stop-Function -Message "Error occurred while getting article columns from $instance" -ErrorRecord $_ -Target $instance -Continue
                // The function never assigns $instance, so the message ends after "from " and the target is $null.
                StopFunction("Error occurred while getting article columns from ", errorRecord: CaughtRecord(failure), continueLoop: true);
                continue;
            }
        }
    }

    // The body of the pin's try block for one article; it returns where the pin runs its continue after the missing-table warning.
    private void EmitColumns(PSObject art)
    {
        RmoArticle article = (RmoArticle)art.BaseObject;

        // PS: $null = $art.LoadProperties()
        LoadArticle(article);

        // PS: $server = $art.SqlInstance; $database = $server.Databases[$art.DatabaseName]
        //     $table = $database.Tables[$art.SourceObjectName, $art.SourceObjectOwner]
        Server server = (Server)art.Properties["SqlInstance"].Value;
        SmoDatabase? database = ReplArticleReader.Get(() => server.Databases[article.DatabaseName], "Databases");
        if (database is null)
            throw new NullIndexException();
        // Correction source-columns: SMO on the server Get-DbaReplArticle attaches lists the connection's current database
        // (master) after RMO used it, so the pin's lookup found nothing and every article that is not vertically partitioned
        // gave no rows. The source table's columns are read in the article's own database instead.
        List<string> allColumns = SourceColumns(server, article);

        if (allColumns.Count == 0)
        {
            WriteMessage(MessageLevel.Warning, String.Format(CultureInfo.InvariantCulture, "Could not find source table [{0}].[{1}] for article {2}",
                article.SourceObjectOwner, article.SourceObjectName, article.Name));
            return;
        }

        // PS: if (-not $art.VerticalPartition) { $columns = $allColumns.Name } else { ...Invoke-DbaQuery...; $columns = $columnData.ColumnName }
        List<string> columns = !article.VerticalPartition ? allColumns : PartitionColumns(server, article);

        // PS: if ($Column) { $columns = $columns | Where-Object { $_ -In $Column } }
        if (PsOps.IsTrue(Column))
            columns = columns.FindAll(name => PsOps.In(name, Column));

        object? computerName = art.Properties["ComputerName"]?.Value;
        object? instanceName = art.Properties["InstanceName"]?.Value;
        object? sqlInstance = art.Properties["SqlInstance"]?.Value;
        bool first = true;
        foreach (string col in columns)
        {
            // Correction same-article-object: the pin re-decorates and emits one article object per column, so collected rows all
            // showed the last column. Each later column gets its own article of the same type, read from the same connection.
            PSObject row = first ? art : DistinctArticle(article);
            first = false;

            // PS: Add-Member -Force ... thirteen notes on the article, then Select-DefaultView with eight properties.
            ReplArticleReader.ReplaceNote(row, "ComputerName", computerName);
            ReplArticleReader.ReplaceNote(row, "InstanceName", instanceName);
            ReplArticleReader.ReplaceNote(row, "SqlInstance", sqlInstance);
            ReplArticleReader.ReplaceNote(row, "DatabaseName", article.DatabaseName);
            ReplArticleReader.ReplaceNote(row, "PublicationName", article.PublicationName);
            ReplArticleReader.ReplaceNote(row, "ArticleName", article.Name);
            ReplArticleReader.ReplaceNote(row, "ArticleId", article.ArticleId);
            ReplArticleReader.ReplaceNote(row, "Description", article.Description);
            ReplArticleReader.ReplaceNote(row, "Type", article.Type);
            ReplArticleReader.ReplaceNote(row, "VerticalPartition", article.VerticalPartition);
            ReplArticleReader.ReplaceNote(row, "SourceObjectOwner", article.SourceObjectOwner);
            ReplArticleReader.ReplaceNote(row, "SourceObjectName", article.SourceObjectName);
            ReplArticleReader.ReplaceNote(row, "ColumnName", col);
            OutputHelper.SetDefaultDisplayPropertySet(row, "ComputerName", "InstanceName", "SqlInstance", "DatabaseName",
                "PublicationName", "ArticleName", "ArticleId", "ColumnName");
            WriteObject(row);
        }
    }

    // PS: Invoke-DbaQuery -SqlInstance $server -Database $art.DatabaseName -Query <pinned query> -SqlParameter @{ articleName; tableName; schemaName }
    // It keeps the server's own connection when that connection is in the article's database and otherwise opens its own
    // there, non-pooled, and closes it after. Called without -EnableException, so a failure is its warning only.
    private List<string> PartitionColumns(Server server, RmoArticle article)
    {
        List<string> columns = new();
        DbaInstanceParameter source = new((object)server);
        ServerConnection serverConnection = server.ConnectionContext;
        ServerConnection connection = serverConnection;
        bool reuse = false;
        bool opened = false;
        try
        {
            reuse = PsString.Eq(serverConnection.CurrentDatabase, article.DatabaseName) && PsString.Eq(serverConnection.ConnectAsUserName, "");
            if (!reuse)
            {
                ServerConnection copy = serverConnection.Copy();
                copy.NonPooledConnection = true;
                connection = copy.GetDatabaseConnection(article.DatabaseName, false);
                connection.StatementTimeout = serverConnection.StatementTimeout;
            }
            if (!connection.IsOpen)
            {
                connection.Connect();
                opened = true;
            }
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            WarnNestedStopFunction(QueryRunner, "Failure", target: source, errorRecord: new ErrorRecord(failure, QueryRunner, ErrorCategory.NotSpecified, null));
            return columns;
        }

        try
        {
            bool merge = article is MergeArticle;
            using SqlCommand command = connection.SqlConnectionObject.CreateCommand();
            command.CommandText = merge ? MergePartitionQuery : PartitionQuery;
            command.CommandTimeout = connection.StatementTimeout;
            command.Parameters.Add("@articleName", SqlDbType.NVarChar, 128).Value = (object?)article.Name ?? DBNull.Value;
            command.Parameters.Add("@publicationName", SqlDbType.NVarChar, 128).Value = (object?)article.PublicationName ?? DBNull.Value;
            if (!merge)
            {
                command.Parameters.Add("@tableName", SqlDbType.NVarChar, 128).Value = (object?)article.SourceObjectName ?? DBNull.Value;
                command.Parameters.Add("@schemaName", SqlDbType.NVarChar, 128).Value = (object?)article.SourceObjectOwner ?? DBNull.Value;
            }
            SetActiveCommand(command);
            using SqlDataReader reader = command.ExecuteReader();
            if (!merge)
            {
                while (reader.Read())
                    columns.Add(reader.GetString(0));
            }
            else
            {
                columns = PublishedMergeColumns(reader);
            }
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            // PS: Resolve-SqlError in the nested query drops the failure under the -ErrorAction this command was given.
            if (!QuietFailure())
            {
                WarnNestedStopFunction(QueryRunner, String.Format(CultureInfo.InvariantCulture, "[{0}] Failed during execution", source), target: source,
                    errorRecord: new ErrorRecord(failure, QueryRunner, ErrorCategory.NotSpecified, null));
            }
        }
        finally
        {
            SetActiveCommand(null);
            if (!reuse || opened)
                connection.Disconnect();
        }
        return columns;
    }

    // The source table's columns in column order, read in the article's database on a connection of its own (non-pooled,
    // closed after), with the table and schema names as parameters. No rows means no such table: a table has at least one
    // column. A failure goes to the caller's catch, where the pin's SMO lookup failure went.
    private List<string> SourceColumns(Server server, RmoArticle article)
    {
        List<string> columns = new();
        ServerConnection serverConnection = server.ConnectionContext;
        ServerConnection copy = serverConnection.Copy();
        copy.NonPooledConnection = true;
        ServerConnection connection = copy.GetDatabaseConnection(article.DatabaseName, false);
        connection.StatementTimeout = serverConnection.StatementTimeout;
        try
        {
            connection.Connect();
            using SqlCommand command = connection.SqlConnectionObject.CreateCommand();
            command.CommandText = SourceColumnQuery;
            command.CommandTimeout = connection.StatementTimeout;
            command.Parameters.Add("@tableName", SqlDbType.NVarChar, 128).Value = (object?)article.SourceObjectName ?? DBNull.Value;
            command.Parameters.Add("@schemaName", SqlDbType.NVarChar, 128).Value = (object?)article.SourceObjectOwner ?? DBNull.Value;
            SetActiveCommand(command);
            using SqlDataReader reader = command.ExecuteReader();
            while (reader.Read())
                columns.Add(reader.GetString(0));
        }
        finally
        {
            SetActiveCommand(null);
            connection.Disconnect();
        }
        return columns;
    }

    // sp_helpmergearticlecolumn's rows (column_id, column_name, published): the published names in column order. Its
    // column_id is sysname (Microsoft Learn), so the order is its numeric value, ties and non-numbers kept in row order.
    private static List<string> PublishedMergeColumns(SqlDataReader reader)
    {
        int idOrdinal = reader.GetOrdinal("column_id");
        int nameOrdinal = reader.GetOrdinal("column_name");
        int publishedOrdinal = reader.GetOrdinal("published");
        List<KeyValuePair<long, string>> published = new();
        while (reader.Read())
        {
            if (reader.IsDBNull(publishedOrdinal) || !Convert.ToBoolean(reader.GetValue(publishedOrdinal), CultureInfo.InvariantCulture))
                continue;
            string id = Convert.ToString(reader.GetValue(idOrdinal), CultureInfo.InvariantCulture) ?? "";
            long order = Int64.TryParse(id, NumberStyles.Integer, CultureInfo.InvariantCulture, out long parsed) ? parsed : Int64.MaxValue;
            published.Add(new KeyValuePair<long, string>(order, Convert.ToString(reader.GetValue(nameOrdinal), CultureInfo.InvariantCulture) ?? ""));
        }
        List<string> columns = new();
        // A stable sort: List.Sort is not, so the row index breaks ties.
        List<int> index = new();
        for (int i = 0; i < published.Count; i++)
            index.Add(i);
        index.Sort((left, right) =>
        {
            int byId = published[left].Key.CompareTo(published[right].Key);
            return byId != 0 ? byId : left.CompareTo(right);
        });
        foreach (int i in index)
            columns.Add(published[i].Value);
        return columns;
    }

    // A fresh article object of the same RMO type for the same article, its properties loaded through the same connection.
    private static PSObject DistinctArticle(RmoArticle article)
    {
        RmoArticle copy = article is MergeArticle
            ? new MergeArticle(article.Name, article.PublicationName, article.DatabaseName, article.ConnectionContext)
            : new TransArticle(article.Name, article.PublicationName, article.DatabaseName, article.ConnectionContext);
        LoadArticle(copy);
        return PSObject.AsPSObject(copy);
    }

    // $article.LoadProperties() as the PowerShell method binder runs it: a failure reaches the catch as a MethodInvocationException.
    private static void LoadArticle(RmoArticle article)
    {
        try
        {
            article.LoadProperties();
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            throw new MethodInvocationException(String.Format(CultureInfo.InvariantCulture,
                "Exception calling \"LoadProperties\" with \"0\" argument(s): \"{0}\"", failure.Message), failure);
        }
    }

    private bool QuietFailure()
    {
        return MyInvocation.BoundParameters.TryGetValue("ErrorAction", out object? bound)
            && bound is ActionPreference.SilentlyContinue or ActionPreference.Ignore;
    }

    // The record the pin's catch receives as $_: indexing the $null a missing database gives raises NullArray.
    private static ErrorRecord CaughtRecord(Exception failure)
    {
        if (failure is NullIndexException)
            return new ErrorRecord(new RuntimeException(failure.Message), "NullArray", ErrorCategory.InvalidOperation, null);
        return ReplArticleReader.CaughtRecord(failure);
    }

    // PowerShell's "Cannot index into a null array." when the article's database is gone from the server's collection.
    private sealed class NullIndexException : Exception
    {
        internal NullIndexException()
            : base("Cannot index into a null array.")
        {
        }
    }
}
