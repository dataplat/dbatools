#nullable enable

using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.IO;
using System.Management.Automation;
using System.Xml;
using Dataplat.Dbatools.dbaSystem;
using Dataplat.Dbatools.Message;
using IOPath = System.IO.Path;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Copies Extended Event session templates from dbatools repository to SSMS template directory for GUI access.
/// </summary>
/// <remarks>
/// The template enumeration is the one Get-DbaXESessionTemplate -Path performs (every *.xml under each
/// directory, its event_session name looked up in bin\xetemplates-metadata.xml), filtered to the templates
/// whose source is not Microsoft, as the pinned function does. Each surviving file is copied into the
/// destination folder, which is created first when it does not exist. A template with no dbatools metadata
/// (one of the caller's own, through -Path) has no Source and is copied (correction custom-templates).
/// </remarks>
[Cmdlet(VerbsCommon.Copy, "DbaXESessionTemplate")]
public sealed class CopyDbaXESessionTemplateCommand : DbaBaseCmdlet
{
    /// <summary>The directory or directories containing Extended Event session template files to copy from.</summary>
    [Parameter(Position = 0)]
    public string[]? Path { get; set; }

    /// <summary>The target directory where Extended Event templates will be installed for SSMS access.</summary>
    [Parameter(Position = 1)]
    public string? Destination { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - the source declares it bare, which the inherited
    // [Parameter] already matches; no override needed.

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        // The pinned defaults, "$script:PSModuleRoot\bin\XEtemplates" and
        // "$home\Documents\SQL Server Management Studio\Templates\XEventTemplates", apply only when unbound.
        string moduleRoot = SystemHost.ModuleBase ?? string.Empty;
        string[]? sourcePaths = TestBound(nameof(Path)) ? Path : new[] { moduleRoot + "\\bin\\XEtemplates" };
        string destination = TestBound(nameof(Destination))
            ? Destination ?? string.Empty
            : Convert.ToString(SessionState.PSVariable.GetValue("HOME")) + "\\Documents\\SQL Server Management Studio\\Templates\\XEventTemplates";

        if (!PathExists(destination))
        {
            try
            {
                Directory.CreateDirectory(ResolvePath(destination));
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception ex)
            {
                // PS: Stop-Function without -Continue or return: the copy below still runs.
                ErrorRecord failure = new ErrorRecord(ex, "DirectoryNotCreated,Copy-DbaXESessionTemplate", ErrorCategory.WriteError, destination);
                StopFunction("Failure", target: destination, errorRecord: failure);
            }
        }

        try
        {
            foreach (string file in GetTemplateFiles(sourcePaths, moduleRoot))
            {
                WriteMessage(MessageLevel.Output, string.Format("Copying {0} to {1}.", IOPath.GetFileName(file), destination));
                CopyTemplate(file, destination);
            }
        }
        catch (PipelineStoppedException)
        {
            throw;
        }
        catch (Exception ex)
        {
            ErrorRecord failure = new ErrorRecord(ex, "TemplateCopyFailed,Copy-DbaXESessionTemplate", ErrorCategory.NotSpecified, sourcePaths);
            StopFunction("Failure", target: sourcePaths, errorRecord: failure);
        }
    }

    /// <summary>
    /// The Path of every template Get-DbaXESessionTemplate -Path returns whose metadata Source is not
    /// Microsoft, in the order it returns them.
    /// </summary>
    private List<string> GetTemplateFiles(string[]? sourcePaths, string moduleRoot)
    {
        // PS: Import-Clixml of the metadata runs first, whatever -Path holds.
        string metadataPath = IOPath.Combine(IOPath.Combine(moduleRoot, "bin"), "xetemplates-metadata.xml");
        object[] metadata = PSSerializer.DeserializeAsList(File.ReadAllText(metadataPath));

        List<string> files = new List<string>();
        if (sourcePaths is null)
        {
            return files;
        }

        foreach (string directory in sourcePaths)
        {
            foreach (string file in GetXmlFiles(directory))
            {
                XmlDocument document = new XmlDocument();
                try
                {
                    document.Load(file);
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch (Exception ex)
                {
                    // PS: Get-DbaXESessionTemplate's own Stop-Function -Continue, which only warns.
                    WriteAttributedMessage("Get-DbaXESessionTemplate", MessageLevel.Warning, "Failure", file, ex);
                    continue;
                }

                XmlElement? root = document.DocumentElement;
                if (root is null || !string.Equals(root.LocalName, "event_sessions", StringComparison.OrdinalIgnoreCase))
                {
                    continue;
                }

                if (IsCopied(SessionName(root), metadata))
                {
                    files.Add(file);
                }
            }
        }

        return files;
    }

    /// <summary>
    /// Get-ChildItem "$(Join-DbaPath $directory *.xml)": the files that match, or the non-terminating
    /// error Get-ChildItem writes when the folder (or the part before a wildcard) or its drive or provider
    /// does not exist, after which the next folder is read.
    /// </summary>
    private List<string> GetXmlFiles(string directory)
    {
        List<string> files = new List<string>();
        string trimmed = directory.TrimEnd('\\', '/');

        // PS: Get-ChildItem reads the children through the same provider intrinsics (no -Recurse, no -Force,
        // wildcards expanded) and, on PSNotSupportedException, DriveNotFoundException,
        // ProviderNotFoundException or ItemNotFoundException, writes new ErrorRecord(e.ErrorRecord, e) and goes
        // on with the next path: same message, category, target and id. The engine adds the writing cmdlet's
        // type to the FullyQualifiedErrorId.
        Collection<PSObject> items;
        try
        {
            items = SessionState.InvokeProvider.ChildItem.Get(new[] { trimmed + "\\*.xml" }, false, false, false);
        }
        catch (Exception lookupFailure) when (lookupFailure is PSNotSupportedException || lookupFailure is System.Management.Automation.DriveNotFoundException || lookupFailure is ProviderNotFoundException || lookupFailure is ItemNotFoundException)
        {
            WriteError(new ErrorRecord(((IContainsErrorRecord)lookupFailure).ErrorRecord, lookupFailure));
            return files;
        }

        foreach (PSObject item in items)
        {
            if (item.BaseObject is FileInfo file)
            {
                files.Add(file.FullName);
            }
        }

        return files;
    }

    /// <summary>
    /// $session.event_session.name: the name attribute of the one event_session child, or null when there is
    /// none (several children make PowerShell return an array, which matches no metadata name either).
    /// </summary>
    private static string? SessionName(XmlElement root)
    {
        XmlElement? session = null;
        int count = 0;
        foreach (XmlNode child in root.ChildNodes)
        {
            if (child is XmlElement element && string.Equals(element.LocalName, "event_session", StringComparison.OrdinalIgnoreCase))
            {
                session = element;
                count++;
            }
        }

        if (count != 1 || session is null || !session.HasAttribute("name"))
        {
            return null;
        }

        return session.GetAttribute("name");
    }

    /// <summary>
    /// Where-Object Source -ne Microsoft over the template object whose Source is the matching metadata
    /// entry's Source.
    /// </summary>
    private static bool IsCopied(string? sessionName, object[] metadata)
    {
        List<PSObject> matches = new List<PSObject>();
        foreach (object entry in metadata)
        {
            PSObject meta = PSObject.AsPSObject(entry);
            if (LanguagePrimitives.Equals(meta.Properties["Name"]?.Value, sessionName, true))
            {
                matches.Add(meta);
            }
        }

        // Correction custom-templates: the pinned enumeration called $meta.Compatibility.ToString() on a
        // template dbatools has no metadata for, which threw and copied nothing from -Path. Such a template
        // has no Source, and $null -ne "Microsoft", so it is copied.
        if (matches.Count == 0)
        {
            return true;
        }

        if (matches.Count == 1)
        {
            return !LanguagePrimitives.Equals(matches[0].Properties["Source"]?.Value, "Microsoft", true);
        }

        List<object?> different = new List<object?>();
        foreach (PSObject meta in matches)
        {
            object? source = meta.Properties["Source"]?.Value;
            if (!LanguagePrimitives.Equals(source, "Microsoft", true))
            {
                different.Add(source);
            }
        }

        return LanguagePrimitives.IsTrue(different.ToArray());
    }

    /// <summary>Copy-Item -Path $file -Destination $destinstance: into the folder, or onto the path itself.</summary>
    private void CopyTemplate(string file, string destination)
    {
        string target = ResolvePath(destination);
        if (Directory.Exists(target))
        {
            target = IOPath.Combine(target, IOPath.GetFileName(file));
        }

        File.Copy(file, target, true);
    }

    private string ResolvePath(string path)
    {
        return SessionState.Path.GetUnresolvedProviderPathFromPSPath(path);
    }

    /// <summary>Test-Path -Path: false for a path that does not exist or cannot be resolved.</summary>
    private bool PathExists(string path)
    {
        try
        {
            string resolved = ResolvePath(path);
            return File.Exists(resolved) || Directory.Exists(resolved);
        }
        catch (PipelineStoppedException)
        {
            throw;
        }
        catch (Exception)
        {
            // Test-Path answers false for a path it cannot resolve.
            return false;
        }
    }
}
