#nullable enable

using System.Management.Automation;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves detailed information about replication articles from SQL Server publications.
/// </summary>
/// <para>
/// Retrieves comprehensive details about articles within SQL Server replication publications, helping DBAs audit and manage replication topology. Articles define which tables, views, or stored procedures are included in a publication for data distribution to subscribers.
/// </para>
/// <para>
/// This function examines all accessible databases on the specified instances and returns article properties including name, type, schema, source objects, and partitioning details. Use this when troubleshooting replication issues, documenting replication setup, or verifying which objects are being replicated across your environment.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaReplArticle -SqlInstance mssql1
/// </code>
/// <para>
/// Retrieve information of all articles from all publications on all databases for server mssql1.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaReplArticle -SqlInstance mssql1 -Database pubs
/// </code>
/// <para>
/// Retrieve information of all articles from all publications on 'pubs' database for server mssql1.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaReplArticle -SqlInstance mssql1 -Database pubs -Publication PubName
/// </code>
/// <para>
/// Retrieve information of all articles from 'PubName' on 'pubs' database for server mssql1.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaReplArticle -SqlInstance mssql1 -Database pubs -Schema sales
/// </code>
/// <para>
/// Retrieve information of articles in the 'sales' schema on 'pubs' database for server mssql1.
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaReplArticle -SqlInstance mssql1 -Database pubs -Publication PubName -Name sales
/// </code>
/// <para>
/// Retrieve information of 'sales' article from 'PubName' on 'pubs' database for server mssql1.
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
/// <seealso href="https://dbatools.io/Get-DbaReplArticle" />
[Cmdlet(VerbsCommon.Get, "DbaReplArticle")]
public sealed class GetDbaReplArticleCommand : ReplArticleHostCmdlet
{
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
    /// Specifies which databases to examine for replication articles. Only articles from publications in these databases will be returned.
    /// Use this when you need to focus on replication articles within specific databases rather than scanning all databases on the instance.
    /// </para>
    [Parameter(Position = 2)]
    public object[]? Database { get; set; }

    /// <para>
    /// Filters results to articles within specific replication publications. Only articles from these named publications will be returned.
    /// Use this when troubleshooting a specific publication or when you need to audit articles within particular publications rather than all publications in the database.
    /// </para>
    [Parameter(Position = 3)]
    public object[]? Publication { get; set; }

    /// <para>
    /// Filters articles by the schema of their source objects (tables, views, or procedures). Only articles whose source objects belong to these schemas will be returned.
    /// Use this when you need to examine replication articles for objects within specific schemas, such as when troubleshooting schema-specific replication issues.
    /// </para>
    [Parameter(Position = 4)]
    public string[]? Schema { get; set; }

    /// <para>
    /// Filters results to articles with specific names. Only articles matching these exact names will be returned.
    /// Use this when you need to examine specific replication articles by name, such as when troubleshooting issues with particular replicated objects.
    /// </para>
    [Parameter(Position = 5)]
    public string[]? Name { get; set; }

    /// <para>
    /// By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    /// This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    /// Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    /// </para>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    protected override void ProcessRecord()
    {
        // PS: if (Test-FunctionInterrupt) { return }
        if (Interrupted)
            return;
        // PS: foreach ($instance in $SqlInstance) - an unbound or null SqlInstance enumerates nothing.
        if (SqlInstance is null)
            return;

        // The process block lives in ReplArticleReader, which Get-DbaReplArticleColumn's nested call shares.
        ReplArticleReader.Read(this, SqlInstance, Database, Publication, Schema, Name, WriteObject);
    }
}
