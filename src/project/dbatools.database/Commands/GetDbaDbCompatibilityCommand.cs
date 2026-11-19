#nullable enable

using System;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;
using SmoDatabase = Microsoft.SqlServer.Management.Smo.Database;

namespace Dataplat.Dbatools.Commands;

/// <summary>Retrieves database compatibility levels from SQL Server instances for upgrade planning and compliance auditing.</summary>
[Cmdlet(VerbsCommon.Get, "DbaDbCompatibility")]
public sealed class GetDbaDbCompatibilityCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) to check.</summary>
    [Parameter(Position = 2)]
    [PsStringArrayCast]
    public string[]? Database { get; set; }

    /// <summary>Database object(s) piped in.</summary>
    [Parameter(ValueFromPipeline = true, Position = 3)]
    public SmoDatabase[]? InputObject { get; set; }

    private bool _instancesRead;

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;
        if (!TestBound(nameof(SqlInstance)) && !TestBound(nameof(InputObject)))
        {
            WriteMessage(MessageLevel.Warning, "You must specify either a SQL instance or pipe a database collection");
            return;
        }

        // The source appends the instance databases to the rebound InputObject on every piped
        // record, repeating the instance rows once per record. SqlInstance is not pipeline-bound,
        // so it is read once, after the first record's piped objects. Pinned help documents
        // wildcards for -Database, which Get-DbaDatabase's exact matching never honoured.
        if (LanguagePrimitives.IsTrue(SqlInstance) && !_instancesRead)
        {
            _instancesRead = true;
            List<SmoDatabase> combined = new(InputObject ?? Array.Empty<SmoDatabase>());
            combined.AddRange(NativeDatabaseSelection.GatherMatching(this, SqlInstance, SqlCredential,
                Database, true, null, false, server => SetActiveConnection(server.ConnectionContext), () => Interrupted));
            InputObject = combined.ToArray();
        }

        foreach (SmoDatabase? database in InputObject ?? Array.Empty<SmoDatabase>())
        {
            if (Interrupted)
                return;
            Server? server = database?.Parent;
            WriteMessage(MessageLevel.Verbose, String.Format("SQL Server is using Version: {0}", server?.VersionMajor));
            PSObject output = new();
            if (server != null)
            {
                OutputHelper.AddInstanceProperties(output, server);
            }
            else
            {
                // Optional arrays can contain null; source property reads then emit null-valued notes.
                output.Properties.Add(new PSNoteProperty("ComputerName", null)); // style-ok: cs-output-props OutputHelper requires a server; preserve the source's explicit null input row.
                output.Properties.Add(new PSNoteProperty("InstanceName", null)); // style-ok: cs-output-props OutputHelper requires a server; preserve the source's explicit null input row.
                output.Properties.Add(new PSNoteProperty("SqlInstance", null)); // style-ok: cs-output-props OutputHelper requires a server; preserve the source's explicit null input row.
            }
            output.Properties.Add(new PSNoteProperty("Database", database?.Name));
            output.Properties.Add(new PSNoteProperty("DatabaseId", database?.ID));
            output.Properties.Add(new PSNoteProperty("Compatibility", database?.CompatibilityLevel));
            WriteObject(output);
        }
    }
}
