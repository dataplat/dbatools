#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Data;
using System.Globalization;
using System.Management.Automation;
using System.Text;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>Retrieves all available collations from SQL Server instances with detailed locale and code page information</summary>
[Cmdlet(VerbsCommon.Get, "DbaAvailableCollation")]
public sealed class GetDbaAvailableCollationCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    // The source's begin-block caches live for the whole pipeline and also memoize failed (null) lookups.
    // The locale cache is seeded with 66577, which Windows no longer supports but SQL Server still reports.
    private readonly Dictionary<object, object?> _locales = new() { { 66577, "Japanese_Unicode" } };
    private readonly Dictionary<object, object?> _codePages = new();

    protected override void ProcessRecord()
    {
        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            if (Interrupted)
                return;
            Server? server = ConnectInstance(instance);
            if (server is null)
                continue;

            DataTable availableCollations;
            try
            {
                availableCollations = server.EnumCollations();
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception exception)
            {
                // caller-try: terminate -- continuing would re-emit the previous instance's collations relabeled for this server
                ThrowTerminatingError(MethodFault("EnumCollations", 0, exception)); // style-ok: cs-raw-streams statement fault outside Stop-Function, as in the source
                return;
            }

            List<PSObject> rows = new();
            foreach (DataRow collation in availableCollations.Rows)
            {
                PSObject row = PSObject.AsPSObject(collation);
                // Add-Member -Force replaces any note an earlier read left on the row.
                foreach (string property in new[] { "ComputerName", "InstanceName", "SqlInstance", "CodePageName", "LocaleName" })
                    row.Properties.Remove(property);
                OutputHelper.AddInstanceProperties(row, server);
                row.Properties.Add(new PSNoteProperty("CodePageName", GetCodePageDescription(collation["CodePage"])));
                row.Properties.Add(new PSNoteProperty("LocaleName", GetLocaleDescription(collation["LocaleID"])));
                rows.Add(row);
            }

            // Select-DefaultView receives the whole DataTable: it shapes every row before emitting them.
            foreach (PSObject row in rows)
            {
                OutputHelper.SetDefaultDisplayPropertySet(row,
                    "ComputerName", "InstanceName", "SqlInstance", "Name", "CodePage", "CodePageName",
                    "LocaleID", "LocaleName", "Description");
            }
            foreach (PSObject row in rows)
                WriteObject(row);
        }
    }

    /// <summary>The source's Get-LocaleDescription: (Get-Language $LocaleId).DisplayName, null on any failure.</summary>
    private object? GetLocaleDescription(object localeId)
    {
        if (_locales.TryGetValue(localeId, out object? cached))
            return cached;
        object? localeName = null;
        if (TryConvertId(localeId, out int id))
        {
            try
            {
                localeName = CultureInfo.GetCultureInfo(id).DisplayName;
            }
            catch (Exception exception)
            {
                // The source's try/catch turns the failure into $null, and the caught record lands in $error.
                InsertCaughtRecord(MethodFault("GetCultureInfo", 1, exception));
            }
        }
        _locales[localeId] = localeName;
        return localeName;
    }

    /// <summary>The source's Get-CodePageDescription: (Get-CodePage $codePageId).EncodingName, null on any failure.</summary>
    private object? GetCodePageDescription(object codePageId)
    {
        if (_codePages.TryGetValue(codePageId, out object? cached))
            return cached;
        object? codePageName = null;
        // Code page 0 marks a Unicode-only collation: it has no code page, so it has no code page name.
        // The source passed 0 to GetEncoding, which returns the client's default encoding instead.
        if (TryConvertId(codePageId, out int id) && id != 0)
        {
            try
            {
                codePageName = Encoding.GetEncoding(id).EncodingName;
            }
            catch (Exception exception)
            {
                // The source's try/catch turns the failure into $null, and the caught record lands in $error.
                InsertCaughtRecord(MethodFault("GetEncoding", 1, exception));
            }
        }
        _codePages[codePageId] = codePageName;
        return codePageName;
    }

    /// <summary>The helpers' [int]$id binding. SMO's EnumCollations columns are Int32, so a failure
    /// cannot occur against a server; it still yields $null, as the source's try/catch does.</summary>
    private static bool TryConvertId(object value, out int id)
    {
        try
        {
            id = LanguagePrimitives.ConvertTo<int>(value);
            return true;
        }
        catch (PSInvalidCastException)
        {
            // Unreachable for Int32 columns; the source's catch would also return $null here.
            id = 0;
            return false;
        }
    }

    /// <summary>The PS catch bookkeeping: a caught terminating record lands in $error.</summary>
    private void InsertCaughtRecord(ErrorRecord record)
    {
        if (SessionState.PSVariable.GetValue("global:Error") is ArrayList errorList)
            errorList.Insert(0, record);
    }

    /// <summary>The ErrorRecord PowerShell builds when a .NET method call in the source throws.</summary>
    private static ErrorRecord MethodFault(string method, int argumentCount, Exception exception)
    {
        MethodInvocationException wrapped = new MethodInvocationException(String.Format(CultureInfo.InvariantCulture,
            "Exception calling \"{0}\" with \"{1}\" argument(s): \"{2}\"", method, argumentCount, exception.Message), exception);
        return new ErrorRecord(wrapped, exception.GetType().Name, ErrorCategory.NotSpecified, null);
    }
}
