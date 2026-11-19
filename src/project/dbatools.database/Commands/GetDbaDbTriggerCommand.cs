#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using SmoDatabase = Microsoft.SqlServer.Management.Smo.Database;

namespace Dataplat.Dbatools.Commands;

// Retrieves database DDL trigger objects and metadata directly through SMO (port of public/Get-DbaDbTrigger.ps1).
/// <summary>Retrieves database-level DDL triggers from SQL Server instances for security auditing and change tracking analysis.</summary>
[Cmdlet(VerbsCommon.Get, "DbaDbTrigger")]
public sealed class GetDbaDbTriggerCommand : DbaBaseCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) to process.</summary>
    [Parameter(Position = 2)]
    public object[]? Database { get; set; }

    /// <summary>The database(s) to exclude.</summary>
    [Parameter(Position = 3)]
    public object[]? ExcludeDatabase { get; set; }

    /// <summary>Database object(s) piped in from Get-DbaDatabase.</summary>
    [Parameter(ValueFromPipeline = true, Position = 4)]
    public SmoDatabase[]? InputObject { get; set; }

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        // PS: $InputObject += Get-DbaDatabase ... inside the process block, so piped records and the
        // gathered databases of this record are processed together.
        List<SmoDatabase> databases = new(InputObject ?? Array.Empty<SmoDatabase>());
        foreach (DbaInstanceParameter instance in SqlInstance ?? Array.Empty<DbaInstanceParameter>())
        {
            // Upstream correction (wrong data): the pinned source passes the whole -SqlInstance array to
            // Get-DbaDatabase on every iteration, so N instances returned every trigger N times; each
            // iteration now gathers only its own instance.
            // Its object-array filters bind to Get-DbaDatabase's string-array filters. Pinned help documents
            // wildcards for -Database only, which Get-DbaDatabase's exact matching never honoured; a real
            // database name of the instance stays literal (rule E+), and -ExcludeDatabase stays literal.
            string[]? include = Database is null ? null :
                (string[])LanguagePrimitives.ConvertTo(Database, typeof(string[]), CultureInfo.InvariantCulture);
            string[]? exclude = ExcludeDatabase is null ? null :
                (string[])LanguagePrimitives.ConvertTo(ExcludeDatabase, typeof(string[]), CultureInfo.InvariantCulture);
            databases.AddRange(NativeDatabaseSelection.GatherMatching(this, new[] { instance }, SqlCredential, include, true, exclude, false,
                server => SetActiveConnection(server.ConnectionContext), () => Interrupted));
        }

        foreach (SmoDatabase database in databases)
        {
            if (Interrupted)
                return;
            if (database is null)
                continue;
            ErrorRecord? error = null;
            try
            {
                IEnumerator triggers;
                try
                {
                    triggers = ((IEnumerable)database.Triggers).GetEnumerator();
                }
                catch (Exception exception) when (!(exception is PipelineStoppedException))
                {
                    // A PowerShell foreach wraps an enumerator-creation failure; SMO loads the
                    // collection there, so a missing or offline database surfaces this record.
                    string wrapped = String.Format(CultureInfo.InvariantCulture,
                        "The following exception occurred while trying to enumerate the collection: \"{0}\".", exception.Message);
                    error = new ErrorRecord(new ExtendedTypeSystemException(wrapped, exception),
                        "ExceptionInGetEnumerator", ErrorCategory.NotSpecified, null);
                    throw;
                }
                while (triggers.MoveNext())
                {
                    PSObject output = PSObject.AsPSObject(triggers.Current);
                    // Add-Member -Force replaces notes left on the same SMO object by an earlier call.
                    foreach (string name in new[] { "ComputerName", "InstanceName", "SqlInstance" })
                        output.Properties.Remove(name);
                    OutputHelper.AddInstanceProperties(output, database.Parent);
                    OutputHelper.SetDefaultDisplayPropertySet(output,
                        "ComputerName", "InstanceName", "SqlInstance", "Name", "IsEnabled", "DateLastModified");
                    WriteObject(output);
                }
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception exception)
            {
                // PS: Stop-Function -Message "Failure" -ErrorRecord $_ -Continue. A script catch sees other
                // .NET exceptions under their type name as OperationStopped.
                error ??= exception is IContainsErrorRecord existing ? existing.ErrorRecord :
                    new ErrorRecord(exception, exception.GetType().FullName, ErrorCategory.OperationStopped, null);
                StopFunction("Failure", errorRecord: error, continueLoop: true);
            }
        }
    }
}
