#nullable enable

using System;
using System.Collections.Generic;
using System.Data;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Parameter;
using Microsoft.SqlServer.Management.Smo;
using SmoDatabase = Microsoft.SqlServer.Management.Smo.Database;

namespace Dataplat.Dbatools.Commands;

// Retrieves data-classification metadata (information type and sensitivity label extended
// properties) for classified columns. Port of public/Get-DbaDbDataClassification.ps1; surface
// pinned by migration/baselines/Get-DbaDbDataClassification.json (positions 0-6, InputObject
// ValueFromPipeline, no ShouldProcess). Earlier Claude reference: refs/fleet/imported/native-batch2
// d88701f2, cb1a0d76, 51d32031 and refs/fleet/imported/native-data-classification 7a6ffb04.
/// <summary>Retrieves data classification information for columns in SQL Server databases</summary>
[Cmdlet(VerbsCommon.Get, "DbaDbDataClassification")]
public sealed class GetDbaDbDataClassificationCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) to process.</summary>
    [Parameter(Position = 2)]
    [PsStringArrayCast]
    public string[]? Database { get; set; }

    /// <summary>Filter to the specified schema(s).</summary>
    [Parameter(Position = 3)]
    [PsStringArrayCast]
    public string[]? Schema { get; set; }

    /// <summary>Filter to the specified table(s).</summary>
    [Parameter(Position = 4)]
    [PsStringArrayCast]
    public string[]? Table { get; set; }

    /// <summary>Filter to the specified column(s).</summary>
    [Parameter(Position = 5)]
    [PsStringArrayCast]
    public string[]? Column { get; set; }

    /// <summary>Database object(s) piped in.</summary>
    [Parameter(ValueFromPipeline = true, Position = 6)]
    public SmoDatabase[]? InputObject { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private const string ClassificationSql = @"
SELECT
    SCHEMA_NAME(o.schema_id) AS SchemaName,
    o.name AS TableName,
    c.name AS ColumnName,
    CAST(ep1.value AS NVARCHAR(MAX)) AS InformationTypeId,
    CAST(ep2.value AS NVARCHAR(MAX)) AS InformationType,
    CAST(ep3.value AS NVARCHAR(MAX)) AS SensitivityLabelId,
    CAST(ep4.value AS NVARCHAR(MAX)) AS SensitivityLabel
FROM sys.objects o
INNER JOIN sys.columns c ON o.object_id = c.object_id
LEFT JOIN sys.extended_properties ep1
    ON ep1.major_id = o.object_id AND ep1.minor_id = c.column_id
    AND ep1.name = 'sys_information_type_id' AND ep1.class = 1
LEFT JOIN sys.extended_properties ep2
    ON ep2.major_id = o.object_id AND ep2.minor_id = c.column_id
    AND ep2.name = 'sys_information_type_name' AND ep2.class = 1
LEFT JOIN sys.extended_properties ep3
    ON ep3.major_id = o.object_id AND ep3.minor_id = c.column_id
    AND ep3.name = 'sys_sensitivity_label_id' AND ep3.class = 1
LEFT JOIN sys.extended_properties ep4
    ON ep4.major_id = o.object_id AND ep4.minor_id = c.column_id
    AND ep4.name = 'sys_sensitivity_label_name' AND ep4.class = 1
WHERE o.type = 'U'
  AND (ep1.value IS NOT NULL OR ep2.value IS NOT NULL OR ep3.value IS NOT NULL OR ep4.value IS NOT NULL)
ORDER BY SCHEMA_NAME(o.schema_id), o.name, c.name";

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        // PS: if ($SqlInstance) { $InputObject = Get-DbaDatabase ... -Database $Database | Where-Object IsAccessible }
        // Upstream correction (wrong data, quality/corrections/Get-DbaDbDataClassification.json): that
        // assignment replaced the given databases, so a database piped or passed to -InputObject alongside
        // -SqlInstance was silently dropped. The given databases are kept, followed by this record's
        // accessible gathered ones.
        List<SmoDatabase?> databases = new(InputObject ?? Array.Empty<SmoDatabase>());
        if (LanguagePrimitives.IsTrue(SqlInstance))
        {
            foreach (SmoDatabase gathered in NativeDatabaseSelection.Gather(this, SqlInstance, SqlCredential, Database, null,
                server => SetActiveConnection(server.ConnectionContext), () => Interrupted))
            {
                if (gathered.IsAccessible)
                    databases.Add(gathered);
            }
        }

        foreach (SmoDatabase? database in databases)
        {
            if (Interrupted)
                return;
            // PS: $null.Parent.VersionMajor -lt 9 is true, so a null element is skipped the same way.
            Server? server = database?.Parent;
            if (database is null || server is null || server.VersionMajor < 9)
            {
                StopFunction(String.Format(CultureInfo.InvariantCulture, "Data classification requires SQL Server 2005 or later. Skipping {0}", server),
                    target: server, continueLoop: true);
                continue;
            }

            DataTable? results;
            try
            {
                // PS: $db.Query($sql), the Database.Query script method: ($this.ExecuteWithResults($Query)).Tables[0]
                SetActiveConnection(server.ConnectionContext);
                DataSet set = database.ExecuteWithResults(ClassificationSql);
                results = set.Tables.Count > 0 ? set.Tables[0] : null;
            }
            catch (Exception failure) when (failure is not PipelineStoppedException)
            {
                StopFunction(String.Format(CultureInfo.InvariantCulture, "Error querying data classifications in {0} on {1}", database.Name, server),
                    target: database, errorRecord: QueryFaultRecord(failure), continueLoop: true);
                continue;
            }
            if (results is null)
                continue;

            foreach (DataRow row in results.Rows)
            {
                if (IsExcluded(Schema, row["SchemaName"]) || IsExcluded(Table, row["TableName"]) || IsExcluded(Column, row["ColumnName"]))
                    continue;

                PSObject output = new();
                output.Properties.Add(new PSNoteProperty("ComputerName", SmoServerExtensions.GetPSProperty(database, "ComputerName"))); // style-ok: cs-output-props the source reads $db.ComputerName from the input database
                output.Properties.Add(new PSNoteProperty("InstanceName", SmoServerExtensions.GetPSProperty(database, "InstanceName"))); // style-ok: cs-output-props the source reads $db.InstanceName from the input database
                output.Properties.Add(new PSNoteProperty("SqlInstance", SmoServerExtensions.GetPSProperty(database, "SqlInstance"))); // style-ok: cs-output-props the source reads $db.SqlInstance from the input database
                output.Properties.Add(new PSNoteProperty("Database", database.Name));
                output.Properties.Add(new PSNoteProperty("Schema", row["SchemaName"]));
                output.Properties.Add(new PSNoteProperty("Table", row["TableName"]));
                output.Properties.Add(new PSNoteProperty("Column", row["ColumnName"]));
                output.Properties.Add(new PSNoteProperty("InformationTypeId", row["InformationTypeId"]));
                output.Properties.Add(new PSNoteProperty("InformationType", row["InformationType"]));
                output.Properties.Add(new PSNoteProperty("SensitivityLabelId", row["SensitivityLabelId"]));
                output.Properties.Add(new PSNoteProperty("SensitivityLabel", row["SensitivityLabel"]));
                output.Properties.Add(new PSNoteProperty("DatabaseObject", database));
                WriteObject(output);
            }
        }
    }

    // PS: if ($Filter -and $row.Value -notin $Filter) { continue }
    private static bool IsExcluded(string[]? filter, object value)
    {
        return LanguagePrimitives.IsTrue(filter) && !NativeDatabaseSelection.ContainsName(filter, value as string ?? "");
    }

    /// <summary>
    /// The record the source catch receives from $db.Query: the .NET call inside the script method
    /// fails as 'Exception calling "ExecuteWithResults"', and the engine reports the script method's
    /// RuntimeException as the ScriptMethodRuntimeException fault of "Query" called with one argument.
    /// </summary>
    private static ErrorRecord QueryFaultRecord(Exception failure)
    {
        MethodInvocationException call = new(String.Format(CultureInfo.InvariantCulture,
            "Exception calling \"ExecuteWithResults\" with \"1\" argument(s): \"{0}\"", failure.Message), failure);
        MethodInvocationException method = new(String.Format(CultureInfo.InvariantCulture,
            "Exception calling \"Query\" with \"1\" argument(s): \"{0}\"", call.Message), call);
        return new ErrorRecord(method, "ScriptMethodRuntimeException", ErrorCategory.NotSpecified, null);
    }
}
