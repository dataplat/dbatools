#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Globalization;
using System.IO;
using System.Management.Automation;
using System.Text;
using System.Text.RegularExpressions;
using System.Xml;
using Dataplat.Dbatools.dbaSystem;
using Dataplat.Dbatools.Utility;
using IOPath = System.IO.Path;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Retrieves Windows Performance Monitor templates designed for SQL Server monitoring and troubleshooting.
/// </summary>
/// <remarks>
/// Port of public/Get-DbaPfDataCollectorSetTemplate.ps1 at refs/pins/dbatools-2026-10-22. The metadata is the module's
/// bin\perfmontemplates\collectorsets.xml read as Import-Clixml reads it; each -Path directory is listed as Get-ChildItem
/// "dir\*.xml" lists it, each file read as Get-Content reads it and cast to [xml] with PowerShell's own conversion, and the
/// template fields are read through the PowerShell XML adapter, so $dataset.name, .useraccount and .Description are the
/// values the pinned function sees.
/// </remarks>
[Cmdlet(VerbsCommon.Get, "DbaPfDataCollectorSetTemplate")]
public sealed class GetDbaPfDataCollectorSetTemplateCommand : DbaBaseCmdlet
{
    /// <summary>
    /// Specifies the directory path containing Performance Monitor template XML files. Defaults to the dbatools built-in template repository (\bin\perfmontemplates\collectorsets).
    /// Use this when you have custom template files stored in a different location or want to load templates from a network share.
    /// </summary>
    [Parameter(Position = 0)]
    public string[]? Path { get; set; }

    /// <summary>
    /// Filters templates by matching text patterns against template names and descriptions using regex syntax. Supports wildcards (* becomes .*).
    /// Use this to find templates for specific scenarios like "long.*query" to locate long-running query monitoring templates.
    /// </summary>
    [Parameter(Position = 1)]
    public string? Pattern { get; set; }

    /// <summary>
    /// Specifies one or more template names to retrieve by exact match. Accepts multiple values and supports tab completion to browse available templates.
    /// Use this when you know the specific template names you need rather than browsing all available templates.
    /// </summary>
    [Parameter(Position = 2)]
    public string[]? Template { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - the source declares it bare, which the inherited [Parameter] matches.

    private static readonly string[] ExcludedColumns = { "File", "Path" };

    private object[]? _metadata;
    private string _pattern = String.Empty;

    /// <summary>Reads the template metadata, applies the -Path default and turns -Pattern's wildcards into regex.</summary>
    protected override void BeginProcessing()
    {
        string moduleRoot = SystemHost.ModuleBase ?? String.Empty;

        // PS: [string[]]$Path = "$script:PSModuleRoot\bin\perfmontemplates\collectorsets", applied only when unbound.
        if (!TestBound(nameof(Path)))
            Path = new[] { moduleRoot + "\\bin\\perfmontemplates\\collectorsets" };

        // PS: $metadata = Import-Clixml "$script:PSModuleRoot\bin\perfmontemplates\collectorsets.xml", outside any try. A
        // failed read leaves $metadata empty and the begin block goes on, so every template then has no Source.
        // Import-Clixml reads the path through the FileSystem provider, which takes "\" as a separator on every platform;
        // System.IO does not on Linux and macOS, so the path is built with the platform's separator.
        string metadataPath = System.IO.Path.Combine(moduleRoot, "bin", "perfmontemplates", "collectorsets.xml");
        try
        {
            _metadata = PSSerializer.DeserializeAsList(File.ReadAllText(metadataPath));
        }
        catch (Exception ex) when (ex is IOException || ex is UnauthorizedAccessException || ex is ArgumentException || ex is NotSupportedException)
        {
            SurfaceFault(new ErrorRecord(ex, "FileOpenFailure", ErrorCategory.OpenError, null));
        }
        catch (XmlException ex)
        {
            SurfaceFault(new ErrorRecord(ex, "System.Xml.XmlException", ErrorCategory.NotSpecified, null));
        }

        // PS: $Pattern = $Pattern.Replace("*", ".*").Replace("..*", ".*"); the unbound [string] reads "".
        _pattern = (Pattern ?? String.Empty).Replace("*", ".*").Replace("..*", ".*");
    }

    /// <summary>Lists the templates of each directory.</summary>
    protected override void ProcessRecord()
    {
        foreach (string directory in Path ?? new string[0])
        {
            List<PSObject> files = ListTemplateFiles(directory);

            // PS: if ($Template): array truth, so @("") or @($null) leaves the files unfiltered (IsTrue(null) is false too).
            string[]? template = Template;
            if (template is not null && LanguagePrimitives.IsTrue(template))
                files = files.FindAll(file => IsIn(file.Properties["BaseName"]?.Value, template));

            foreach (PSObject file in files)
            {
                XmlDocument? xml;
                try
                {
                    xml = ReadTemplate(file);
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch (Exception ex) when (ex is PSInvalidCastException || ex is RuntimeException)
                {
                    // PS: catch { Stop-Function -Message "Failure" -ErrorRecord $_ -Target $file -Continue }
                    ErrorRecord failure = (ex as IContainsErrorRecord)?.ErrorRecord ?? new ErrorRecord(ex, "InvalidCastToXmlDocument", ErrorCategory.InvalidArgument, null);
                    StopFunction("Failure", target: file, errorRecord: failure, continueLoop: true);
                    continue;
                }

                if (xml is null)
                    continue;

                // PS: foreach ($dataset in $xml.DataCollectorSet): the adapter's root element (or elements), never their children.
                foreach (object? dataset in Enumerate(AdapterValue(xml, "DataCollectorSet")))
                {
                    if (dataset is null)
                        continue;
                    EmitTemplate(dataset, file);
                }
            }
        }
    }

    private void EmitTemplate(object dataset, PSObject file)
    {
        object? name = AdapterValue(dataset, "name");
        object? description = AdapterValue(dataset, "Description");

        if (_pattern.Length > 0)
        {
            // PS: if (($dataset.Name -match $Pattern) -or ($dataset.Description -match $Pattern)) - one statement, outside any
            // try: an invalid pattern fails it and the loop goes on with the next template.
            Regex? regex = PatternRegex(out ErrorRecord? invalidPattern);
            if (regex is null)
            {
                SurfaceFault(invalidPattern!);
                return;
            }

            if (!Matches(AdapterValue(dataset, "Name"), regex) && !Matches(description, regex))
                return;
        }

        // PS: $meta = $metadata | Where-Object Name -eq $dataset.name; Source = $meta.Source.
        List<object?> sources = new List<object?>();
        foreach (object entry in _metadata ?? new object[0])
        {
            PSObject meta = PSObject.AsPSObject(entry);
            if (LanguagePrimitives.Equals(meta.Properties["Name"]?.Value, name, true, CultureInfo.InvariantCulture))
                sources.Add(meta.Properties["Source"]?.Value);
        }

        object? source = sources.Count == 0 ? null : sources.Count == 1 ? sources[0] : sources.ToArray();

        PSObject row = new PSObject();
        row.Properties.Add(new PSNoteProperty("Name", name));
        row.Properties.Add(new PSNoteProperty("Source", source));
        row.Properties.Add(new PSNoteProperty("UserAccount", AdapterValue(dataset, "useraccount")));
        row.Properties.Add(new PSNoteProperty("Description", description));
        row.Properties.Add(new PSNoteProperty("Path", file));
        row.Properties.Add(new PSNoteProperty("File", file.Properties["Name"]?.Value));
        OutputHelper.SetDefaultDisplayPropertySetExcluding(row, ExcludedColumns);
        WriteObject(row);
    }

    /// <summary>
    /// PS: Get-ChildItem "$directory\*.xml": the provider's children (no -Recurse, no -Force, wildcards expanded). A path the
    /// provider cannot read writes Get-ChildItem's non-terminating record and lists nothing.
    /// </summary>
    private List<PSObject> ListTemplateFiles(string directory)
    {
        List<PSObject> files = new List<PSObject>();
        Collection<PSObject> items;
        try
        {
            items = SessionState.InvokeProvider.ChildItem.Get(new[] { directory + "\\*.xml" }, false, false, false);
        }
        catch (Exception lookupFailure) when (lookupFailure is PSNotSupportedException || lookupFailure is System.Management.Automation.DriveNotFoundException || lookupFailure is ProviderNotFoundException || lookupFailure is ItemNotFoundException)
        {
            WriteError(new ErrorRecord(((IContainsErrorRecord)lookupFailure).ErrorRecord, lookupFailure));
            return files;
        }

        foreach (PSObject item in items)
        {
            if (item.BaseObject is FileSystemInfo)
                files.Add(item);
        }

        return files;
    }

    /// <summary>
    /// PS: $xml = [xml](Get-Content $file). Get-Content reads the lines in the edition's default encoding (a byte order mark
    /// wins); an empty file gives $null, which [xml] keeps. The cast is PowerShell's own string-to-XmlDocument conversion, so
    /// a file that is not XML fails with the record the pinned catch receives. A file Get-Content cannot read writes its
    /// non-terminating record and gives $null.
    /// </summary>
    private XmlDocument? ReadTemplate(PSObject file)
    {
        if (file.BaseObject is not FileInfo info)
            return null;

        string[] lines;
        try
        {
            lines = File.ReadAllLines(info.FullName, Encoding.Default);
        }
        catch (UnauthorizedAccessException ex)
        {
            WriteError(new ErrorRecord(ex, "GetContentReaderUnauthorizedAccessError", ErrorCategory.PermissionDenied, info.FullName));
            return null;
        }
        catch (IOException ex)
        {
            WriteError(new ErrorRecord(ex, "GetContentReaderIOError", ErrorCategory.ReadError, info.FullName));
            return null;
        }

        if (lines.Length == 0)
            return null;
        object content = lines.Length == 1 ? lines[0] : lines;
        return (XmlDocument)LanguagePrimitives.ConvertTo(content, typeof(XmlDocument), CultureInfo.InvariantCulture);
    }

    /// <summary>
    /// PS: -match builds new Regex(pattern, IgnoreCase) for each use. An invalid pattern raises .NET's own parse exception
    /// as the record (the pin probe of 2026-11-11 on both editions: the exception's type name as the error id,
    /// OperationStopped, no target; ArgumentException on Windows PowerShell, RegexParseException on PowerShell 7).
    /// </summary>
    private Regex? PatternRegex(out ErrorRecord? fault)
    {
        fault = null;
        try
        {
            return new Regex(_pattern, RegexOptions.IgnoreCase);
        }
        catch (ArgumentException ex)
        {
            fault = new ErrorRecord(ex, ex.GetType().FullName, ErrorCategory.OperationStopped, null);
            return null;
        }
    }

    /// <summary>
    /// PS: $value -match $regex. A collection keeps its matching elements, which decide the if as an array does; anything
    /// else is matched as its string ($null as "").
    /// </summary>
    private static bool Matches(object? value, Regex regex)
    {
        if (value is not string && LanguagePrimitives.GetEnumerable(value) is IEnumerable elements)
        {
            List<object?> matched = new List<object?>();
            foreach (object? element in elements)
            {
                if (regex.IsMatch(AsText(element)))
                    matched.Add(element);
            }
            return LanguagePrimitives.IsTrue(matched.ToArray());
        }

        return regex.IsMatch(AsText(value));
    }

    private static string AsText(object? value)
    {
        if (value is null)
            return String.Empty;
        return LanguagePrimitives.ConvertTo<string>(value) ?? String.Empty;
    }

    /// <summary>A member read through the PowerShell adapter ($object.name), $null when there is no such member.</summary>
    private static object? AdapterValue(object target, string name)
    {
        PSPropertyInfo? property = PSObject.AsPSObject(target).Properties[name];
        if (property is null)
            return null;
        object? value = property.Value;
        return value is PSObject wrapped ? wrapped.BaseObject : value;
    }

    /// <summary>PS foreach over a value: a collection's elements (the engine never enumerates an XmlNode), else the value.</summary>
    private static IEnumerable Enumerate(object? value)
    {
        if (value is null)
            return new object[0];
        if (value is not XmlNode && LanguagePrimitives.GetEnumerable(value) is IEnumerable elements)
            return elements;
        return new[] { value };
    }

    /// <summary>PS: $value -in $list, PowerShell's case-insensitive equality.</summary>
    private static bool IsIn(object? value, string[] list)
    {
        foreach (string candidate in list)
        {
            if (LanguagePrimitives.Equals(value, candidate, true, CultureInfo.InvariantCulture))
                return true;
        }
        return false;
    }

    // A statement of the pin outside any try: a plain call writes the record and goes on, a caller's try catches it,
    // -EnableException stops here.
    private void SurfaceFault(ErrorRecord fault)
    {
        if (EnableException.ToBool())
        {
            // caller-try: terminate -- -EnableException asks for the stop
            ThrowTerminatingError(fault); // style-ok: cs-raw-streams a statement fault outside Stop-Function, as in the pin
        }

        StatementFault.Surface(this, fault);
    }
}
