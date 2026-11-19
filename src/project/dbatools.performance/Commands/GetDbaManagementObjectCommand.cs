#nullable enable

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Management.Automation;
using System.Management.Automation.Remoting;
using System.Management.Automation.Runspaces;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;
using Dataplat.Dbatools.Configuration;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;

namespace Dataplat.Dbatools.Commands;

// Port of public/Get-DbaManagementObject.ps1 at refs/pins/dbatools-2026-10-22. The pin's begin-block script block runs in this
// process for the local computer (its name or "localhost") and in a remote session otherwise. Here the local computer is read with
// .NET (the AppDomain's assemblies, this process's modules, the GAC folders) and a remote computer through a remote runspace that
// runs single commands with the values as parameters (Get-Item, Get-Variable, Get-ChildItem, Get-Process); the rows are built here
// as the script block builds them.
/// <summary>Discovers installed SQL Server Management Object (SMO) assemblies and their load status</summary>
/// <para>
/// Scans the system for SQL Server Management Object (SMO) assemblies, SqlClient libraries, and SNI modules to help troubleshoot version conflicts and connectivity issues. This function checks both the Global Assembly Cache (GAC) and currently loaded assemblies in the PowerShell session, returning version information, load status, file paths, and ready-to-use Add-Type commands. Particularly useful when diagnosing why different SQL Server tools behave differently or when you need to load specific SMO versions in PowerShell scripts.
/// </para>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaManagementObject
/// </code>
/// <para>
/// Returns all versions of SMO on the computer
/// </para>
/// </example>
/// <example>
/// <code>
/// PS C:\&gt; Get-DbaManagementObject -VersionNumber 13
/// </code>
/// <para>
/// Returns just the version specified. If the version does not exist then it will return nothing.
/// </para>
/// </example>
/// <list type="alertSet">
/// <item>
/// <term />
/// <description>
/// <para>
/// Tags: SMO
/// Author: Ben Miller (@DBAduck), dbaduck.com
/// </para>
/// <para>
/// Website: https://dbatools.io
/// Copyright: (c) 2018 by dbatools, licensed under MIT
/// License: MIT https://opensource.org/licenses/MIT
/// </para>
/// </description>
/// </item>
/// </list>
/// <seealso href="https://dbatools.io/Get-DbaManagementObject" />
[Cmdlet(VerbsCommon.Get, "DbaManagementObject")]
public sealed class GetDbaManagementObjectCommand : DbaBaseCmdlet
{
    private const string SmoTokenTail = ", Culture=neutral, PublicKeyToken=89845dcd8080cc91\"";
    private const string DefaultShellUri = "http://schemas.microsoft.com/powershell/Microsoft.PowerShell";

    /// <para>
    /// Specifies the Windows server(s) where you want to scan for SMO assemblies and SQL Client libraries.
    /// Use this when troubleshooting SMO version conflicts across multiple servers or when checking which SQL Server tools are installed on remote machines.
    /// </para>
    [Parameter(ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[]? ComputerName { get; set; } = DefaultComputerName();

    /// <para>
    /// This command uses Windows credentials. This parameter allows you to connect remotely as a different user.
    /// </para>
    [Parameter(Position = 1)]
    public PSCredential? Credential { get; set; }

    /// <para>
    /// Filters results to show only assemblies matching the specified major version number (e.g., 13 for SQL Server 2016, 14 for 2017, 15 for 2019).
    /// Use this when you need to verify if a specific SQL Server version's SMO libraries are installed, particularly when troubleshooting version compatibility issues between different SQL Server tools.
    /// </para>
    [Parameter(Position = 2)]
    public int VersionNumber { get; set; }

    // Overridden only to carry the pinned .PARAMETER EnableException help; same bare [Parameter] as the base.
    /// <para>
    /// By default, when something goes wrong we try to catch it, interpret it and give you a friendly warning message.
    /// This avoids overwhelming you with "sea of red" exceptions, but is inconvenient because it basically disables advanced scripting.
    /// Using this switch turns this "nice by default" feature off and enables you to catch exceptions with your own try/catch.
    /// </para>
    [Parameter]
    public override SwitchParameter EnableException { get; set; }

    // PS: [DbaInstanceParameter[]]$ComputerName = $env:COMPUTERNAME; an unset variable leaves the parameter null.
    private static DbaInstanceParameter[]? DefaultComputerName()
    {
        string? name = Environment.GetEnvironmentVariable("COMPUTERNAME");
        return String.IsNullOrEmpty(name) ? null : new[] { new DbaInstanceParameter(name) };
    }

    protected override void ProcessRecord()
    {
        // PS: foreach ($computer in $ComputerName.ComputerName); member enumeration skips null elements.
        List<string> computers = new();
        foreach (DbaInstanceParameter? item in ComputerName ?? Array.Empty<DbaInstanceParameter>())
        {
            if (item is not null)
                computers.Add(item.ComputerName);
        }

        foreach (string computer in computers)
        {
            try
            {
                WriteMessage(MessageLevel.Verbose, "Executing scriptblock against " + computer);
                bool local = String.Equals(computer, Environment.GetEnvironmentVariable("COMPUTERNAME"), StringComparison.OrdinalIgnoreCase)
                    || String.Equals(computer, "localhost", StringComparison.OrdinalIgnoreCase);
                if (local)
                    ReadInProcess(false);
                else if (new DbaInstanceParameter(computer).IsLocalHost)
                    ReadInProcess(true); // PS: Invoke-Command2 runs the script block here, with -ArgumentList $VersionNumber, $true, for a local address or name
                else
                    ReadRemote(computer);
            }
            catch (PipelineStoppedException)
            {
                throw;
            }
            catch (Exception ex)
            {
                StopFunction("Failure", target: ComputerName, errorRecord: StatementFault.Record(ex, "Get-DbaManagementObject"), continueLoop: true);
            }
        }
    }

    // One loaded assembly as the script block sees it: its FullName, Location and the version string it derives.
    private sealed class LoadedAssembly
    {
        internal LoadedAssembly(string fullName, string location, string? version)
        {
            FullName = fullName;
            Location = location;
            Version = version;
        }

        internal string FullName { get; }
        internal string Location { get; }
        internal string? Version { get; }
    }

    // One SNI module: its file name and its FileVersionInfo.FileVersion, "Unknown" when there is none.
    private sealed class SniModule
    {
        internal SniModule(string? fileName, string version)
        {
            FileName = fileName;
            Version = version;
        }

        internal string? FileName { get; }
        internal string Version { get; }
    }

    // PS: Where-Object { $_.Fullname -like "Microsoft.SqlServer.SMO,*" -or ... -like "*.smo.*" -or ... -like "*SqlClient*" -or ... "*sqlclient*sni*" }
    private static readonly WildcardPattern[] AssemblyPatterns =
    {
        new("Microsoft.SqlServer.SMO,*", WildcardOptions.IgnoreCase),
        new("*.smo.*", WildcardOptions.IgnoreCase),
        new("*SqlClient*", WildcardOptions.IgnoreCase),
        new("*sqlclient*sni*", WildcardOptions.IgnoreCase),
    };

    private static readonly WildcardPattern SniPattern = new("*SNI*", WildcardOptions.IgnoreCase);

    // True while a remote session runs the script block: its Write-Verbose lines stay in that session.
    private bool _quiet;

    // True for rows Invoke-Command2 returns: its Select-Object -Property * names them Selected.<type>.
    private bool _selected;

    private static readonly Regex VersionPart = new("Version=([^,]+)", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);

    // ---------- the local computer: the script block's work in this process ----------

    // remoteBranch: the script block's $remote argument, true when Invoke-Command2 runs it here for a local address; its rows then
    // pass through Invoke-Command2's Select-Object.
    private void ReadInProcess(bool remoteBranch)
    {
        string computerName = Environment.GetEnvironmentVariable("COMPUTERNAME") ?? "";
        _selected = remoteBranch;

        // Correction local-version-number: the pin ran the local script block with no -ArgumentList, so its $VersionNumber was
        // always 0 there and -VersionNumber did nothing for the local computer; here the local computer filters as a remote one does.
        int versionNumber = VersionNumber;
        PlainVerbose("Checking currently loaded SMO, SqlClient, and related assemblies");
        List<LoadedAssembly> loaded = new();
        foreach (Assembly assembly in AppDomain.CurrentDomain.GetAssemblies())
        {
            string fullName = assembly.FullName ?? "";
            if (AssemblyPatterns.Any(pattern => pattern.IsMatch(fullName)))
                loaded.Add(new LoadedAssembly(fullName, assembly.Location, LoadedVersion(fullName, assembly.Location)));
        }

        ReportLoaded(loaded);
        List<SniModule> sniModules = ReadSniModules(LocalSniModules);
        if (!remoteBranch)
            WriteLibraryRows(computerName, loaded, versionNumber);

        bool onWindows = !RuntimeInformation.IsOSPlatform(OSPlatform.Linux) && !RuntimeInformation.IsOSPlatform(OSPlatform.OSX);
        if (onWindows && !WriteGacRows(computerName, loaded, LocalSystemRoot(), LocalFolderNames, versionNumber))
            return;

        WriteSniRows(computerName, sniModules, loaded);
    }

    // PS: if (-not $remote) - the included library row, then the loaded assemblies its version does not cover.
    private void WriteLibraryRows(string computerName, List<LoadedAssembly> loaded, int versionNumber)
    {
        string? libLocation = loaded.Count > 0 ? loaded[0].Location : null;
        PlainVerbose("Looking for included smo library at " + libLocation);
        Version? localVersion = null;
        if (libLocation is not null)
        {
            // PS: [version]((Get-ChildItem -Path $liblocation).VersionInfo.ProductVersion -split "\+" | Select-Object -First 1)
            string? product = FileVersionInfo.GetVersionInfo(libLocation).ProductVersion;
            localVersion = LanguagePrimitives.ConvertTo<Version>((product ?? "").Split('+')[0]);
        }

        // With a version the filtered row keeps the library path (correction local-version-number): the pin's version branch read
        // $loadedversion.Location, a property its version strings lack, and the row reported no path.
        if (localVersion is not null && Wanted(localVersion.ToString(), "Did not pass a version", versionNumber))
        {
            bool isLoaded = loaded.Any(item => SameMajorMinor(item.Version, localVersion));
            WriteRow(computerName, localVersion.ToString(), isLoaded, libLocation ?? "", "Add-Type -Path " + libLocation);
        }

        foreach (LoadedAssembly assembly in loaded)
        {
            Match version = VersionPart.Match(assembly.FullName);
            if (!version.Success || version.Groups[1].Value.Length == 0)
                continue;
            if (localVersion is not null && SameMajorMinor(version.Groups[1].Value, localVersion))
                continue;
            WriteRow(computerName, version.Groups[1].Value, true, assembly.Location, "Add-Type -Path \"" + assembly.Location + "\"");
        }
    }

    private static List<SniModule> LocalSniModules()
    {
        List<SniModule> found = new();
        foreach (ProcessModule module in Process.GetCurrentProcess().Modules)
        {
            if (SniPattern.IsMatch(module.ModuleName ?? ""))
                found.Add(new SniModule(module.FileName, FileVersionOf(module)));
        }

        return found;
    }

    private static List<string> LocalFolderNames(string path)
    {
        try
        {
            if (!Directory.Exists(path))
                return new List<string>();
            return Directory.GetDirectories(path).Select(folder => Path.GetFileName(folder) ?? "").ToList();
        }
        catch (Exception ex) when (ex is IOException || ex is UnauthorizedAccessException)
        {
            // PS: Get-ChildItem ... -ErrorAction Ignore
            return new List<string>();
        }
    }

    private static string FileVersionOf(ProcessModule module)
    {
        try
        {
            string? version = module.FileVersionInfo?.FileVersion;
            return String.IsNullOrEmpty(version) ? "Unknown" : version!;
        }
        catch (Exception ex) when (ex is not PipelineStoppedException)
        {
            // PS: catch { # Ignore version extraction errors }
            return "Unknown";
        }
    }

    // ---------- a remote computer: the same steps in a remote session ----------

    private void ReadRemote(string computer)
    {
        // PS: Invoke-Command2 -ComputerName $computer -Credential $Credential -ErrorAction Stop: a session with the PSRemoting.* settings.
        bool ssl = LanguagePrimitives.IsTrue(RemotingSetting("psremoting.pssession.usessl"));
        int port = ssl ? 5986 : 5985;
        if (LanguagePrimitives.TryConvertTo(RemotingSetting("psremoting.pssession.port"), out int configured) && configured > 0)
        {
            WriteAttributedMessage("Invoke-Command2", MessageLevel.Verbose, "Using Port: " + configured.ToString(CultureInfo.InvariantCulture));
            port = configured;
        }

        // Fully qualified: Dataplat.Dbatools.Runspace is a namespace, and it hides the type's simple name here.
        using System.Management.Automation.Runspaces.Runspace session = RunspaceFactory.CreateRunspace(new WSManConnectionInfo(ssl, computer, port, "/wsman", SessionConfiguration(), Credential)
        {
            SkipRevocationCheck = LanguagePrimitives.IsTrue(RemotingSetting("psremoting.pssessionoption.skiprevocationcheck")),
            SkipCNCheck = LanguagePrimitives.IsTrue(RemotingSetting("psremoting.pssessionoption.skipcncheck")),
            SkipCACheck = LanguagePrimitives.IsTrue(RemotingSetting("psremoting.pssessionoption.skipcacheck")),
            IncludePortInSPN = LanguagePrimitives.IsTrue(RemotingSetting("psremoting.pssessionoption.includeportinspn")),
            IdleTimeout = 600000,
        });
        try
        {
            session.Open();
        }
        catch (PSRemotingTransportException ex)
        {
            // PS: New-PSSession -ErrorAction Stop reports a session that fails to open as PSSessionOpenFailed, category OpenError,
            // which Stop-Function keeps (probe pin-mgmtobject-20261106, unreachable-enable-exception).
            throw new RuntimeException(ex.Message, ex, new ErrorRecord(ex, "PSSessionOpenFailed", ErrorCategory.OpenError, computer));
        }

        // The remote session keeps its own preferences: the script block's Write-Verbose lines stay there (probe
        // pin-mgmtobject-20261106, remote-verbose), and its rows pass through Invoke-Command2's Select-Object.
        _selected = true;
        _quiet = true;
        try
        {
            ReadRemoteSession(session);
        }
        finally
        {
            _quiet = false;
        }
    }

    // PS: Invoke-Command2 gives New-PSSession no -ConfigurationName, so the session opens on the caller's
    // $PSSessionConfigurationName, by default the Microsoft.PowerShell configuration. A bare configuration name gets the
    // http://schemas.microsoft.com/powershell/ prefix from WSManConnectionInfo, as about_Preference_Variables describes for the
    // variable. Read from the caller's scope, as PowerShell reads a preference for a compiled command.
    private string SessionConfiguration()
    {
        object? value = SessionState.PSVariable.GetValue("PSSessionConfigurationName");
        if (value is PSObject wrapped)
            value = wrapped.BaseObject;
        string? name = value as string;
        return String.IsNullOrEmpty(name) ? DefaultShellUri : name!;
    }

    private void ReadRemoteSession(System.Management.Automation.Runspaces.Runspace session)
    {
        string computerName = RemoteEnvironment(session, "Env:COMPUTERNAME");
        string systemRoot = RemoteEnvironment(session, "Env:SystemRoot");

        // A remote session runs no dbatools and loads no SMO or SqlClient assembly, so the script block finds none there. Measured,
        // not assumed: probe dd10904b (pin-mgmtobject-20261106, evidence/pin-mgmtobject-20261106.txt, sqlcluster node SQLNODE1, both
        // editions) shows the pin's remote rows with Loaded=False, and an independent read of the remote session's AppDomain finds no
        // SMO or SqlClient assembly and no SNI module (case remote-independent). On a session configuration that preloads SMO or
        // SqlClient the pin can show Loaded=True or an SNI LoadTemplate and this port does not: an accepted difference installed by
        // the operator (harness-edits.md, "Get-DbaManagementObject: remote Loaded on a custom session configuration", 2026-11-07),
        // since another process's AppDomain cannot be read without running code inside it; the follow-up stays open.
        List<LoadedAssembly> loaded = new();
        ReportLoaded(loaded);
        List<SniModule> sniModules = ReadSniModules(() => RemoteSniModules(session));

        bool onWindows = !LanguagePrimitives.IsTrue(RemoteVariable(session, "IsLinux")) && !LanguagePrimitives.IsTrue(RemoteVariable(session, "IsMacOS"));
        if (onWindows && !WriteGacRows(computerName, loaded, systemRoot, path => RemoteFolderNames(session, path), VersionNumber))
            return;

        WriteSniRows(computerName, sniModules, loaded);
    }

    private string RemoteEnvironment(System.Management.Automation.Runspaces.Runspace session, string path)
    {
        using (PowerShell read = PowerShell.Create().AddCommand("Get-Item").AddParameter("LiteralPath", path))
        {
            read.Runspace = session;
            return RunRemote(read).FirstOrDefault()?.Properties["Value"]?.Value as string ?? "";
        }
    }

    private object? RemoteVariable(System.Management.Automation.Runspaces.Runspace session, string name)
    {
        using (PowerShell read = PowerShell.Create().AddCommand("Get-Variable").AddParameter("Name", name).AddParameter("ValueOnly").AddParameter("ErrorAction", ActionPreference.Ignore))
        {
            read.Runspace = session;
            return RunRemote(read).FirstOrDefault()?.BaseObject;
        }
    }

    private List<string> RemoteFolderNames(System.Management.Automation.Runspaces.Runspace session, string path)
    {
        using (PowerShell list = PowerShell.Create().AddCommand("Get-ChildItem").AddParameter("Path", path).AddParameter("ErrorAction", ActionPreference.Ignore))
        {
            list.Runspace = session;
            return RunRemote(list).Select(item => item.Properties["Name"]?.Value as string ?? "").ToList();
        }
    }

    // PS: Get-Process -Id $PID | ForEach-Object { $_.Modules | Where-Object { $_.ModuleName -like '*SNI*' } } in the session's process.
    private List<SniModule> RemoteSniModules(System.Management.Automation.Runspaces.Runspace session)
    {
        object? remoteId = RemoteVariable(session, "PID");
        using (PowerShell modules = PowerShell.Create().AddCommand("Get-Process").AddParameter("Id", remoteId).AddParameter("Module").AddParameter("ErrorAction", ActionPreference.Stop).AddCommand("Where-Object").AddParameter("Property", "ModuleName").AddParameter("Like").AddParameter("Value", "*SNI*").AddCommand("Select-Object").AddParameter("ExpandProperty", "FileVersionInfo"))
        {
            modules.Runspace = session;
            return RunRemote(modules)
                .Select(info => new SniModule(info.Properties["FileName"]?.Value as string, info.Properties["FileVersion"]?.Value is string version && version.Length > 0 ? version : "Unknown"))
                .ToList();
        }
    }

    // One command in the session. An error that ends it ends the call for this computer, as the pin's -ErrorAction Stop does.
    private List<PSObject> RunRemote(PowerShell command)
    {
        IAsyncResult pending = command.BeginInvoke();
        while (!pending.AsyncWaitHandle.WaitOne(250))
        {
            if (CancellationToken.IsCancellationRequested)
                command.Stop();
        }

        if (CancellationToken.IsCancellationRequested)
            throw new PipelineStoppedException();
        return command.EndInvoke(pending).Where(item => item is not null).ToList();
    }

    // ---------- shared by both paths ----------

    private static string LocalSystemRoot() => Environment.GetEnvironmentVariable("SystemRoot") ?? "";

    // PS: Get-DbatoolsConfigValue -FullName <name>, as Invoke-Command2 reads its PSRemoting.* settings.
    private static object? RemotingSetting(string name)
    {
        ConfigurationHost.Configurations.TryGetValue(name, out Config? setting);
        return setting?.Value;
    }

    // PS: if ($_.FullName -match "Version=([^,]+)") { $matches[1] } elseif ($_.Location -match "__") { ... } else { ProductVersion }
    private static string? LoadedVersion(string fullName, string location)
    {
        Match version = VersionPart.Match(fullName);
        if (version.Success)
            return version.Groups[1].Value;
        if (location.Contains("__"))
            return (Path.GetFileName(Path.GetDirectoryName(location)) ?? "").Split(new[] { "__" }, StringSplitOptions.None)[0];
        return FileVersionInfo.GetVersionInfo(location).ProductVersion;
    }

    private void ReportLoaded(List<LoadedAssembly> loaded)
    {
        if (loaded.Count > 0)
            PlainVerbose("Found " + loaded.Count.ToString(CultureInfo.InvariantCulture) + " loaded SQL-related assemblies: " + String.Join(", ", loaded.Select(item => item.FullName)));
        else
            PlainVerbose("No SQL-related assemblies currently loaded in AppDomain");
    }

    // PS: the try around the SNI module read; a failure is a verbose line and no modules.
    private List<SniModule> ReadSniModules(Func<List<SniModule>> read)
    {
        try
        {
            List<SniModule> modules = read();
            if (modules.Count > 0)
                PlainVerbose("Found " + modules.Count.ToString(CultureInfo.InvariantCulture) + " SNI modules: " + String.Join(", ", modules.Select(module => Path.GetFileName(module.FileName))));
            return modules;
        }
        catch (Exception ex) when (ex is not PipelineStoppedException)
        {
            PlainVerbose("Error checking for SNI modules: " + ex.Message);
            return new List<SniModule>();
        }
    }

    // The script block's -VersionNumber filter with its verbose lines: true when the row is wanted.
    private bool Wanted(string version, string allMessage, int versionNumber)
    {
        if (versionNumber == 0)
        {
            PlainVerbose(allMessage);
            return true;
        }

        string number = versionNumber.ToString(CultureInfo.InvariantCulture);
        PlainVerbose("Passed version " + number + ", looking for that specific version");
        if (!version.StartsWith(number + ".", StringComparison.Ordinal))
            return false;
        PlainVerbose("Found the Version " + number);
        return true;
    }

    // PS: [version]$loadedVer, then its Major and Minor against the library version.
    private static bool SameMajorMinor(string? loadedVersion, Version library)
    {
        Version? parsed = LanguagePrimitives.ConvertTo<Version>(loadedVersion);
        return parsed is not null && parsed.Major == library.Major && parsed.Minor == library.Minor;
    }

    // PS: the GAC folders, newest name first. False when there is none: the script block's bare continue ends this computer.
    private bool WriteGacRows(string computerName, List<LoadedAssembly> loaded, string systemRoot, Func<string, List<string>> folderNames, int versionNumber)
    {
        List<string> names = folderNames(systemRoot + "\\assembly\\GAC_MSIL\\Microsoft.SqlServer.Smo");
        bool second = false;
        if (names.Count == 0)
        {
            // PS: -Filter "*$number.*" | Where-Object FullName -match "_$number" with $number never set: every folder.
            names = folderNames(systemRoot + "\\Microsoft.NET\\assembly\\GAC_MSIL\\Microsoft.SqlServer.Smo");
            second = true;
        }

        if (names.Count == 0)
        {
            PlainVerbose("No SMO versions found in GAC");
            return false;
        }

        foreach (string name in names.OrderByDescending(name => name, StringComparer.Create(CultureInfo.CurrentCulture, true)))
        {
            string[] parts = name.Split('_');
            string current = second ? (parts.Length > 1 ? parts[1] : "") : parts[0];
            if (!Wanted(current, "Did not pass a version, looking for all versions", versionNumber))
                continue;
            bool isLoaded = loaded.Any(item => String.Equals(item.Version, current, StringComparison.OrdinalIgnoreCase));
            WriteRow(computerName, current, isLoaded, null, "Add-Type -AssemblyName \"Microsoft.SqlServer.Smo, Version=" + current + SmoTokenTail);
        }

        return true;
    }

    // PS: one row per SNI module, with the Add-Type template of the SqlClient assembly beside it when one is loaded.
    private void WriteSniRows(string computerName, List<SniModule> sniModules, List<LoadedAssembly> loaded)
    {
        foreach (SniModule module in sniModules)
        {
            string sniPath = module.FileName ?? "";
            List<LoadedAssembly> clients = loaded.Where(item => item.FullName.IndexOf("SqlClient", StringComparison.OrdinalIgnoreCase) >= 0 && SniBesideClient(sniPath, item.Location)).ToList();
            string? folder = Path.GetDirectoryName(sniPath);
            while (clients.Count == 0 && !String.IsNullOrEmpty(folder))
            {
                folder = Path.GetDirectoryName(folder);
                string candidate = Path.Combine(folder ?? "", "Microsoft.Data.SqlClient.dll");
                clients = loaded.Where(item => String.Equals(item.Location, candidate, StringComparison.OrdinalIgnoreCase)).ToList();
            }

            // PS: [string]$sqlClientAssembly.Location over one or more matches.
            string clientPath = String.Join(" ", clients.Select(item => item.Location));
            string template = clientPath.Length > 0 ? "Add-Type -Path \"" + clientPath + "\" -ReferencedAssemblies \"" + sniPath + "\"" : "";
            WriteRow(computerName, module.Version, true, sniPath, template);
        }
    }

    // PS: $sniPath -like "*<the folder three levels above the assembly>*"
    private static bool SniBesideClient(string sniPath, string clientLocation)
    {
        string root = Path.GetDirectoryName(Path.GetDirectoryName(Path.GetDirectoryName(clientLocation))) ?? "";
        return new WildcardPattern("*" + root + "*", WildcardOptions.IgnoreCase).IsMatch(sniPath);
    }

    // PS: [PSCustomObject]@{ ComputerName; Version; Loaded; Path; LoadTemplate }; Path is $null only on the GAC rows.
    private void WriteRow(string computerName, string version, bool loaded, string? path, string template)
    {
        PSObject row = new();
        row.Properties.Add(new PSNoteProperty("ComputerName", computerName)); // style-ok: cs-output-props the pin's [string]$env:COMPUTERNAME of the computer read, its own five-property row with no display set
        row.Properties.Add(new PSNoteProperty("Version", version));
        row.Properties.Add(new PSNoteProperty("Loaded", loaded));
        row.Properties.Add(new PSNoteProperty("Path", path));
        row.Properties.Add(new PSNoteProperty("LoadTemplate", template));
        if (_selected)
            row.TypeNames.Insert(0, "Selected.System.Management.Automation.PSCustomObject");
        WriteObject(row);
    }

    // PS: Write-Verbose inside the script block ("DO NOT use Write-Message as this is inside of a script block"): no prefix.
    private void PlainVerbose(string message)
    {
        if (_quiet)
            return;
        WriteVerbose(message); // style-ok: cs-raw-streams the pin's script block writes plain Write-Verbose lines, never Write-Message
    }
}
