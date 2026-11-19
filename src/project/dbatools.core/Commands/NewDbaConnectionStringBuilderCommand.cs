#nullable enable

using System;
using System.Data.Common;
using System.Management.Automation;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Creates a SqlConnectionStringBuilder object for constructing properly formatted SQL Server connection strings
/// </summary>
/// <remarks>
/// Returns a SqlConnectionStringBuilder built from a connection string plus parameter
/// overrides. Port of public/New-DbaConnectionStringBuilder.ps1 (W1-028). Both the modern
/// Microsoft.Data.SqlClient and Legacy System.Data.SqlClient builders are constructed
/// natively, and both are driven
/// through the DbConnectionStringBuilder base (ShouldSerialize + virtual indexer). The
/// guard warns PER PIPELINE ITEM (the function's Stop-Function + return only exits that
/// process block), so ProcessRecord deliberately does NOT gate on Interrupted. Positions
/// 0-8 pin the PS implicit positional binding (non-switch parameters numbered
/// consecutively; switches never positional).
/// Surface pinned by migration/baselines/New-DbaConnectionStringBuilder.json.
/// </remarks>
[Cmdlet(VerbsCommon.New, "DbaConnectionStringBuilder")]
public sealed class NewDbaConnectionStringBuilderCommand : DbaBaseCmdlet
{
    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    [Parameter(ValueFromPipeline = true, Position = 0)]
    public string[] ConnectionString { get; set; } = new[] { "" };

    [Parameter(Position = 1)]
    [PsStringCast]
    public string? ApplicationName { get; set; } = "dbatools Powershell Module";

    [Parameter(Position = 2)]
    [Alias("SqlInstance")]
    [PsStringCast]
    public string? DataSource { get; set; }

    [Parameter(Position = 3)]
    public PSCredential? SqlCredential { get; set; }

    [Parameter(Position = 4)]
    [Alias("Database")]
    [PsStringCast]
    public string? InitialCatalog { get; set; }

    [Parameter]
    public SwitchParameter IntegratedSecurity { get; set; }

    [Parameter(Position = 5)]
    [PsStringCast]
    public string? UserName { get; set; }

    [Parameter(Position = 6)]
    [PsStringCast]
    public string? Password { get; set; }

    [Parameter]
    [Alias("MARS")]
    public SwitchParameter MultipleActiveResultSets { get; set; }

    [Parameter(Position = 7)]
    [Alias("AlwaysEncrypted")]
    [PsStringCast]
    [ValidateSet("Enabled")]
    public string? ColumnEncryptionSetting { get; set; }

    [Parameter]
    public SwitchParameter Legacy { get; set; }

    [Parameter]
    public SwitchParameter NonPooledConnection { get; set; }

    [Parameter(Position = 8)]
    [PsStringCast]
    public string? WorkstationID { get; set; }

    protected override void BeginProcessing()
    {
        // PS param default: [string]$WorkstationID = $env:COMPUTERNAME at bind time.
        if (!TestBound("WorkstationID"))
            WorkstationID = Environment.GetEnvironmentVariable("COMPUTERNAME") ?? "";
    }

    protected override void ProcessRecord()
    {
        bool pooling = !NonPooledConnection.ToBool();
        if (LanguagePrimitives.IsTrue(SqlCredential) && (LanguagePrimitives.IsTrue(UserName) || LanguagePrimitives.IsTrue(Password)))
        {
            // PS: Stop-Function ... -EnableException $EnableException; return - exits THIS
            // process block only, so the warning repeats for every pipeline item.
            ReportFailure("You can only specify SQL Credential or Username/Password, not both.");
            return;
        }
        if (LanguagePrimitives.IsTrue(SqlCredential))
        {
            UserName = SqlCredential!.UserName;
            Password = SqlCredential.GetNetworkCredential().Password;
        }

        foreach (string cs in ConnectionString ?? Array.Empty<string>())
        {
            DbConnectionStringBuilder builder;
            try
            {
                // -Legacy explicitly promises the obsolete System.Data provider.
#pragma warning disable CS0618
                builder = Legacy.ToBool()
                    ? new System.Data.SqlClient.SqlConnectionStringBuilder(cs)
                    : new Microsoft.Data.SqlClient.SqlConnectionStringBuilder(cs);
#pragma warning restore CS0618
            }
            catch (Exception exception) when (exception is ArgumentException || exception is FormatException || exception is OverflowException)
            {
                // A failed source constructor reused the previous builder or emitted null.
                // Reject that item without leaking its connection string into diagnostics.
                // This protects the warning text; error records retain provider details.
                ReportFailure("The connection string is invalid.", exception, suppressProviderMessage: true);
                continue;
            }

            try
            {
                ApplyOverrides(builder, pooling);
            }
            catch (ArgumentException exception)
            {
                // Do not emit a connection that silently omits a rejected option.
                ReportFailure("The connection string overrides are invalid.", exception);
                continue;
            }
            WriteObject(builder);
        }
    }

    private void ApplyOverrides(DbConnectionStringBuilder builder, bool pooling)
    {
        if (!builder.ShouldSerialize("Application Name"))
            builder["Application Name"] = ApplicationName;
        if (TestBound("DataSource"))
            builder["Data Source"] = DataSource;
        if (TestBound("InitialCatalog"))
            builder["Initial Catalog"] = InitialCatalog;
        if (TestBound("IntegratedSecurity"))
        {
            if (IntegratedSecurity.ToBool())
                builder["Integrated Security"] = true;
            else
                builder["Integrated Security"] = false;
        }
        if (LanguagePrimitives.IsTrue(UserName))
        {
            builder["User ID"] = UserName;
        }
        else if (!IntegratedSecurity.ToBool())
        {
            builder["Integrated Security"] = false;
        }
        if (LanguagePrimitives.IsTrue(Password))
            builder["Password"] = Password;
        if (!builder.ShouldSerialize("Workstation ID"))
            builder["Workstation ID"] = WorkstationID;
        if (TestBound("WorkstationID"))
            builder["Workstation ID"] = WorkstationID;
        if (TestBound("MultipleActiveResultSets"))
        {
            if (MultipleActiveResultSets.ToBool())
                builder["MultipleActiveResultSets"] = true;
            else
                builder["MultipleActiveResultSets"] = false;
        }
        if (PsString.Eq(ColumnEncryptionSetting, "Enabled"))
            builder["Column Encryption Setting"] = "Enabled";
        if (!builder.ShouldSerialize("Pooling"))
            builder["Pooling"] = pooling;
        if (TestBound("NonPooledConnection"))
            builder["Pooling"] = pooling;
    }

    private void ReportFailure(string message, Exception? exception = null, bool suppressProviderMessage = false)
    {
        // caller-try: continue -- invalid input or a rejected override leaves only stale, null or partial output; reject that item and preserve later inputs (recorded correction). EnableException still terminates here.
        StopFunction(message, exception: exception, overrideExceptionMessage: suppressProviderMessage);
    }

}
