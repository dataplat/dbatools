#nullable enable

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Computer;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves page file settings from computers.
/// Port of public/Get-DbaPageFileSetting.ps1; surface pinned by migration/baselines/Get-DbaPageFileSetting.json.
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaPageFileSetting")]
[OutputType(typeof(PageFileSetting))]
public sealed class GetDbaPageFileSettingCommand : DbaBaseCmdlet
{
    /// <summary>The target computer(s); defaults to the local computer.</summary>
    [Parameter(ValueFromPipeline = true, ValueFromPipelineByPropertyName = true, Position = 0)]
    public DbaInstanceParameter[]? ComputerName { get; set; } = DefaultComputerName();

    /// <summary>Credential object used to connect to the computer as a different user.</summary>
    [Parameter(Position = 1)]
    public PSCredential? Credential { get; set; }

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        if (ComputerName is null)
        {
            return;
        }

        foreach (DbaInstanceParameter computer in ComputerName)
        {
            List<PSObject> pageFiles = new();
            List<PSObject> pageFileUsages = new();
            List<PSObject> pageFileSettings = new();
            object? automaticManaged = null;
            try
            {
                CimService.CmObjectResult compSys = QueryOne(computer, "SELECT * FROM win32_computersystem");
                if (compSys.Instances.Count > 0)
                {
                    automaticManaged = compSys.Instances[0].Properties["AutomaticManagedPagefile"]?.Value;
                }
                // PS: if (-not $CompSys.automaticmanagedpagefile) { ...query the three pagefile classes... }
                if (!IsTrue(automaticManaged))
                {
                    pageFiles = QueryOne(computer, "SELECT * FROM win32_pagefile").Instances;
                    pageFileUsages = QueryOne(computer, "SELECT * FROM win32_pagefileUsage").Instances;
                    pageFileSettings = QueryOne(computer, "SELECT * FROM win32_pagefileSetting").Instances;
                }
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception ex)
            {
                StopFunction($"Failed to retrieve information from {computer.ComputerName}", target: computer, errorRecord: new ErrorRecord(ex, "dbatools_Get-DbaPageFileSetting", ErrorCategory.NotSpecified, computer), continueLoop: true);
                continue;
            }

            if (!IsTrue(automaticManaged))
            {
                foreach (PSObject file in pageFiles)
                {
                    string? fileName = GetValue(file, "Name")?.ToString();
                    PSObject? settings = FirstByName(pageFileSettings, fileName);
                    PSObject? usage = FirstByName(pageFileUsages, fileName);

                    // PS: New-Object -Property fails the whole statement when a date value
                    // cannot convert (the Wmi-rung DMTF string shape): an error record, no
                    // object for this file, and the loop moves on (cross-model review
                    // 2026-07-06 pm2 finding 8).
                    object? lastModifiedRaw = GetValue(file, "LastModified");
                    object? lastAccessedRaw = GetValue(file, "LastAccessed");
                    if ((lastModifiedRaw is not null && lastModifiedRaw is not DateTime) || (lastAccessedRaw is not null && lastAccessedRaw is not DateTime))
                    {
                        WriteError(new ErrorRecord(new PSInvalidOperationException("The value supplied is not valid, or the property is read-only. Change the value, and then try again."), "dbatools_Get-DbaPageFileSetting", ErrorCategory.InvalidOperation, file));
                        continue;
                    }

                    // pagefile is not automatic managed, so return settings
                    PageFileSetting row = new();
                    row.ComputerName = computer.ComputerName;
                    row.AutoPageFile = IsTrue(automaticManaged);
                    row.FileName = fileName;
                    row.Status = GetValue(file, "Status")?.ToString();
                    // PS: ($settings.InitialSize -eq 0) -and ($settings.MaximumSize -eq 0)
                    // - a missing settings row compares $null -eq 0 = false.
                    row.SystemManaged = settings is not null && ToLong(GetValue(settings, "InitialSize")) == 0 && ToLong(GetValue(settings, "MaximumSize")) == 0;
                    row.LastModified = (DateTime?)lastModifiedRaw;
                    row.LastAccessed = (DateTime?)lastAccessedRaw;
                    row.AllocatedBaseSize = ToNullableInt(GetValue(usage, "AllocatedBaseSize")); // in MB, between Initial and Maximum Size
                    row.InitialSize = ToNullableInt(GetValue(settings, "InitialSize")); // in MB
                    row.MaximumSize = ToNullableInt(GetValue(settings, "MaximumSize")); // in MB
                    row.PeakUsage = ToNullableInt(GetValue(usage, "PeakUsage")); // in MB
                    row.CurrentUsage = ToNullableInt(GetValue(usage, "CurrentUsage")); // in MB
                    WriteObject(row);
                }
            }
            else
            {
                // pagefile is automatic managed, so there are no settings
                // PS: ComputerName = $computer (the input object) string-converts via
                // DbaInstanceParameter.ToString() to FullSmoName, NOT FullName (codex parity fix
                // 2026-07-10: identical for a bare host name, differs for connection-string forms
                // like "TCP:sql01,51433").
                PageFileSetting row = new();
                row.ComputerName = computer.ToString();
                row.AutoPageFile = IsTrue(automaticManaged);
                row.FileName = null;
                row.Status = null;
                row.SystemManaged = null;
                row.LastModified = null;
                row.LastAccessed = null;
                row.AllocatedBaseSize = null;
                row.InitialSize = null;
                row.MaximumSize = null;
                row.PeakUsage = null;
                row.CurrentUsage = null;
                WriteObject(row);
            }
        }
    }

    private CimService.CmObjectResult QueryOne(DbaInstanceParameter computer, string query)
    {
        // PS: $splatDbaCmObject = @{ ComputerName; EnableException = $true } (+ Credential
        // only when the caller supplied one)
        CimService.CmObjectRequest request = new()
        {
            ComputerName = computer.ComputerName,
            Query = query
        };
        if (Credential is not null)
        {
            request.Credential = Credential;
        }
        CimService.CmObjectResult result = CimService.GetCmObject(this, request);
        foreach (ErrorRecord error in result.PassthroughErrors)
        {
            WriteError(NestedCommand.PreserveErrorIdentity(error));
        }
        return result;
    }

    private static PSObject? FirstByName(List<PSObject> instances, string? name)
    {
        foreach (PSObject instance in instances)
        {
            string? candidate = instance.Properties["Name"]?.Value?.ToString();
            if (string.Equals(candidate, name, StringComparison.OrdinalIgnoreCase))
            {
                return instance;
            }
        }
        return null;
    }

    private static object? GetValue(PSObject? instance, string name)
    {
        return instance?.Properties[name]?.Value;
    }

    private static bool IsTrue(object? value)
    {
        return value is not null && LanguagePrimitives.IsTrue(value);
    }

    private static long ToLong(object? value)
    {
        if (value is null)
        {
            return -1;
        }
        return Convert.ToInt64(value, CultureInfo.InvariantCulture);
    }

    private static int? ToNullableInt(object? value)
    {
        if (value is null)
        {
            return null;
        }
        return Convert.ToInt32(value, CultureInfo.InvariantCulture);
    }

    private static DbaInstanceParameter[]? DefaultComputerName()
    {
        string? machine = Environment.GetEnvironmentVariable("COMPUTERNAME");
        if (string.IsNullOrEmpty(machine))
        {
            return null;
        }
        return new[] { new DbaInstanceParameter(machine) };
    }
}
