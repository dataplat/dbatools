#nullable enable

using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.dbaSystem;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves JSON template files that define column structures for generating realistic test data
/// </summary>
[Cmdlet(VerbsCommon.Get, "DbaRandomizedDatasetTemplate")]
public sealed class GetDbaRandomizedDatasetTemplateCommand : DbaBaseCmdlet
{
    /// <summary>Filter to the specified template(s) by base name.</summary>
    [Parameter(Position = 0)]
    public string[]? Template { get; set; }

    /// <summary>Additional path(s) to search for template files.</summary>
    [Parameter(Position = 1)]
    public string[]? Path { get; set; }

    /// <summary>Exclude the built-in default templates.</summary>
    [Parameter]
    public SwitchParameter ExcludeDefault { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    private readonly List<PSObject> _templates = new List<PSObject>();

    protected override void BeginProcessing()
    {
        if (!ExcludeDefault)
            Gather(System.IO.Path.Combine(SystemHost.ModuleBase, "bin", "randomizer", "templates", "*.json"));
    }

    protected override void ProcessRecord()
    {
        if (Interrupted)
            return;

        // Correction per-directory-path: each directory is resolved once, in caller order.
        foreach (string directory in Path ?? Array.Empty<string>())
            Gather((directory ?? "") + System.IO.Path.DirectorySeparatorChar + "*.json");

        foreach (PSObject item in _templates)
        {
            object? name = item.Properties["BaseName"]?.Value;
            if (LanguagePrimitives.IsTrue(Template))
            {
                bool matched = false;
                foreach (string filter in Template!)
                    if (LanguagePrimitives.Equals(name, filter, true, CultureInfo.InvariantCulture))
                    {
                        matched = true;
                        break;
                    }
                if (!matched)
                    continue;
            }

            PSObject output = new PSObject();
            output.Properties.Add(new PSNoteProperty("BaseName", name));
            output.Properties.Add(new PSNoteProperty("FullName", item.Properties["FullName"]?.Value));
            if (item.TypeNames.Count > 0)
                output.TypeNames.Insert(0, "Selected." + item.TypeNames[0]);
            WriteObject(output);
        }
    }

    private void Gather(string pattern)
    {
        Collection<PathInfo> paths;
        try
        {
            paths = SessionState.Path.GetResolvedPSPathFromPSPath(pattern);
        }
        catch (Exception failure) when (IsProviderFault(failure))
        {
            WriteError(new ErrorRecord(((IContainsErrorRecord)failure).ErrorRecord, failure));
            return;
        }

        // Correction empty-resolution-working-directory: only resolved template paths are enumerated.
        // No Get-ChildItem-equivalent call is made without a path, so unrelated current-directory rows cannot leak in.
        foreach (PathInfo path in paths)
            ReadItems(path.Path);
    }

    private void ReadItems(string path)
    {
        try
        {
            _templates.AddRange(SessionState.InvokeProvider.ChildItem.Get(new[] { path }, false, false, false));
        }
        catch (Exception failure) when (IsProviderFault(failure))
        {
            // These are provider non-terminating records: caller try and EnableException do not stop the pin.
            WriteError(new ErrorRecord(((IContainsErrorRecord)failure).ErrorRecord, failure));
        }
    }

    private static bool IsProviderFault(Exception failure)
    {
        return failure is PSNotSupportedException || failure is DriveNotFoundException ||
            failure is ProviderNotFoundException || failure is ItemNotFoundException || failure is ProviderInvocationException;
    }
}
