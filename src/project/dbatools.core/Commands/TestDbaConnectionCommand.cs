#nullable enable

using System;
using System.Collections.Generic;
using System.Management.Automation;
using System.Net.NetworkInformation;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Composite connectivity diagnostic. Port of public/Test-DbaConnection.ps1 (W1-039).
/// Per instance: the loop-carried result variables reset first (issue #9066 comment
/// preserved below); the local-environment bag reads the SESSION's PSVersionTable plus
/// native OS/identity APIs; Resolve-DbaNetworkName (still-PS, hardcoded -EnableException)
/// rides an outcome-as-data hop whose failure routes to the exact Stop-Function -Continue
/// site; the PSRemoting probe runs the verbatim Invoke-Command2 Get-ChildItem call and
/// stores $true or the CAUGHT RECORD as the output value, exactly like the function; the
/// ping is the same undisposed Ping.Send with a 1000ms timeout; the connect rides the REAL
/// Connect-DbaInstance (warning-capture parity) and its failure runs Stop-Function WITHOUT
/// -Continue, so the result object still emits with ConnectSuccess false; Get-DbaTcpPort
/// and Test-DbaConnectionAuthScheme failures store their caught records as the property
/// values. Output is the function's 21-property object in declaration order.
/// Positions: SqlInstance 0, Credential 1, SqlCredential 2.
/// Surface pinned by migration/baselines/Test-DbaConnection.json.
/// </summary>
[Cmdlet(VerbsDiagnostic.Test, "DbaConnection")]
public sealed class TestDbaConnectionCommand : DbaBaseCmdlet
{
    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    [Parameter(ValueFromPipeline = true, Position = 0)]
    public DbaInstanceParameter[]? SqlInstance { get; set; }

    [Parameter(Position = 1)]
    public PSCredential? Credential { get; set; }

    [Parameter(Position = 2)]
    public PSCredential? SqlCredential { get; set; }

    [Parameter]
    public SwitchParameter SkipPSRemoting { get; set; }

    // The function's loop-reset block names ONLY authType/tcpport/authscheme (#9066);
    // $server and $username are FUNCTION-SCOPE locals that persist across the instance
    // loop AND across pipeline process-block invocations, so a later instance whose
    // connect fails emits the PREVIOUS row's SqlVersion and ConnectingAsUser (codex
    // r1+r2 - faithful quirk carried as cmdlet fields, not fixed).
    private object? username;
    private Server? server;

    protected override void ProcessRecord()
    {
        if (SqlInstance is null)
            return;

        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            // Clear loop variables assigned after connection test - https://github.com/dataplat/dbatools/issues/9066
            object? authType = null;
            object? tcpport = null;
            object? authscheme = null;

            // Get local environment
            WriteMessage(MessageLevel.Verbose, "Getting local environment information");
            object? versionTable = SessionState.PSVariable.GetValue("PSVersionTable");
            string localWindows = Environment.OSVersion.Version.ToString();
            // PS: $PSVersionTable.<key> is HASHTABLE key access, not property access.
            object? localEdition = GetTableEntry(versionTable, "PSEdition");
            // PS: $PSVersionTable.PSVersion.ToString() is a METHOD CALL - a missing entry
            // dies method-on-null, unlike the [string] cast below (codex r1).
            object? psVersionEntry = GetTableEntry(versionTable, "PSVersion");
            if (psVersionEntry is null)
                throw new PSInvalidOperationException("You cannot call a method on a null-valued expression.");
            string localPowerShell = PsToText(psVersionEntry);
            // PS: [string]$PSVersionTable.CLRVersion - null renders empty.
            string localClr = PsToText(GetTableEntry(versionTable, "CLRVersion"));
            string? localSmo = GetLoadedSmoVersion();
            // PS: $env:computername -ne $env:USERDOMAIN (case-insensitive)
            bool localDomainUser = !PsString.Eq(Environment.GetEnvironmentVariable("COMPUTERNAME"), Environment.GetEnvironmentVariable("USERDOMAIN"));
            bool localRunAsAdmin;
#if NET8_0_OR_GREATER
            if (!OperatingSystem.IsWindows())
            {
                // PS: [Security.Principal.WindowsIdentity]::GetCurrent() throws this same
                // exception off-Windows; the analyzer just wants the guard spelled out.
                throw new PlatformNotSupportedException("Windows Principal functionality is not supported on this platform.");
            }
#endif
            using (System.Security.Principal.WindowsIdentity identity = System.Security.Principal.WindowsIdentity.GetCurrent())
            {
                localRunAsAdmin = new System.Security.Principal.WindowsPrincipal(identity).IsInRole(System.Security.Principal.WindowsBuiltInRole.Administrator);
            }

            // PS: try { $resolved = Resolve-DbaNetworkName -ComputerName $instance.ComputerName -Credential $Credential -EnableException }
            // catch { Stop-Function -Message "Unable to resolve server information" -Category ConnectionError -Target $instance -ErrorRecord $_ -Continue }
            PSObject? resolved = null;
            ErrorRecord? resolveError = null;
            foreach (PSObject item in NestedCommand.InvokeScoped(this, ResolveScript, instance.ComputerName, Credential))
            {
                ErrorRecord? caught = ExtractCaughtError(item);
                if (caught is not null)
                    resolveError = caught;
                else
                    resolved = item;
            }
            if (resolveError is not null)
            {
                StopFunction("Unable to resolve server information", target: instance, errorRecord: resolveError, category: ErrorCategory.ConnectionError, continueLoop: true);
                continue;
            }

            // Test for WinRM #Test-WinRM
            object? remoting = null;
            if (SkipPSRemoting.ToBool())
            {
                WriteMessage(MessageLevel.Verbose, "Checking remote access will be skipped");
            }
            else
            {
                WriteMessage(MessageLevel.Verbose, "Checking remote access");
                remoting = true;
                foreach (PSObject item in NestedCommand.InvokeScoped(this, RemotingScript, instance.ComputerName, Credential))
                {
                    ErrorRecord? caught = ExtractCaughtError(item);
                    if (caught is not null)
                        remoting = caught;
                }
            }

            // Test Connection first using Ping class which requires ICMP access then fail back to tcp if pings are blocked
            WriteMessage(MessageLevel.Verbose, "Testing ping to " + instance.ComputerName);
            Ping ping = new Ping();
            const int timeout = 1000; //milliseconds
            bool pingable;
            try
            {
                PingReply reply = ping.Send(instance.ComputerName, timeout);
                // PS: $reply.Status -eq 'Success' (enum vs string, case-insensitive)
                pingable = reply.Status == IPStatus.Success;
            }
            catch
            {
                pingable = false;
            }

            bool connectSuccess;
            object? instanceName;
            // PS: $server = Connect-DbaInstance ... inside the try - a failed connect never
            // assigns, so server/username keep the PREVIOUS iteration's values (see the
            // loop-persistence note above the foreach).
            ErrorRecord? connectError = null;
            foreach (PSObject item in NestedCommand.InvokeScoped(this, ConnectScript, instance, SqlCredential))
            {
                ErrorRecord? caught = ExtractCaughtError(item);
                if (caught is not null)
                    connectError = caught;
                else
                    server = PsAssignment.Unwrap(item) as Server;
            }
            if (connectError is null && server is not null)
            {
                connectSuccess = true;
                instanceName = server.InstanceName;
                // PS: if (-not $instanceName) { $instanceName = $instance.InstanceName }
                if (!LanguagePrimitives.IsTrue(instanceName))
                    instanceName = instance.InstanceName;

                username = server.ConnectionContext.TrueLogin;
                // PS: if ($username -like "*\*") - case-insensitive wildcard contains
                if (username is string userText && userText.Contains("\\"))
                    authType = "Windows Authentication";
                else
                    authType = "SQL Authentication";

                // TCP Port
                // PS: try { $tcpport = (Get-DbaTcpPort ... -EnableException).Port } catch { $tcpport = $_ }
                List<PSObject> portResults = new List<PSObject>();
                ErrorRecord? portError = null;
                foreach (PSObject item in NestedCommand.InvokeScoped(this, TcpPortScript, instance, SqlCredential, Credential))
                {
                    ErrorRecord? caught = ExtractCaughtError(item);
                    if (caught is not null)
                        portError = caught;
                    else
                        portResults.Add(item);
                }
                tcpport = portError is not null ? portError : ProjectMember(portResults, "Port");

                // Auth Scheme
                // PS: try { $authscheme = (Test-DbaConnectionAuthScheme -SqlInstance $server -EnableException).AuthScheme } catch { $authscheme = $_ }
                List<PSObject> schemeResults = new List<PSObject>();
                ErrorRecord? schemeError = null;
                foreach (PSObject item in NestedCommand.InvokeScoped(this, AuthSchemeScript, server))
                {
                    ErrorRecord? caught = ExtractCaughtError(item);
                    if (caught is not null)
                        schemeError = caught;
                    else
                        schemeResults.Add(item);
                }
                authscheme = schemeError is not null ? schemeError : ProjectMember(schemeResults, "AuthScheme");
            }
            else
            {
                connectSuccess = false;
                instanceName = instance.InstanceName;
                // PS: Stop-Function "Failure" WITHOUT -Continue - non-EE warns and execution
                // falls through to the result emission below; EE throws out of the cmdlet.
                StopFunction("Failure", target: instance, errorRecord: connectError, category: ErrorCategory.ConnectionError);
            }

            PSObject output = new PSObject();
            output.Properties.Add(new PSNoteProperty("ComputerName", PsProperty.Get(resolved, "ComputerName")));
            output.Properties.Add(new PSNoteProperty("InstanceName", instanceName));
            output.Properties.Add(new PSNoteProperty("SqlInstance", instance.FullSmoName));
            output.Properties.Add(new PSNoteProperty("SqlVersion", server?.Version));
            output.Properties.Add(new PSNoteProperty("ConnectingAsUser", username));
            output.Properties.Add(new PSNoteProperty("ConnectSuccess", connectSuccess));
            output.Properties.Add(new PSNoteProperty("AuthType", authType));
            output.Properties.Add(new PSNoteProperty("AuthScheme", authscheme));
            output.Properties.Add(new PSNoteProperty("TcpPort", tcpport));
            output.Properties.Add(new PSNoteProperty("IPAddress", PsProperty.Get(resolved, "IPAddress")));
            output.Properties.Add(new PSNoteProperty("NetBiosName", PsProperty.Get(resolved, "FullComputerName")));
            output.Properties.Add(new PSNoteProperty("IsPingable", pingable));
            output.Properties.Add(new PSNoteProperty("PSRemotingAccessible", remoting));
            output.Properties.Add(new PSNoteProperty("DomainName", PsProperty.Get(resolved, "Domain")));
            output.Properties.Add(new PSNoteProperty("LocalWindows", localWindows));
            output.Properties.Add(new PSNoteProperty("LocalPowerShell", localPowerShell));
            output.Properties.Add(new PSNoteProperty("LocalCLR", localClr));
            output.Properties.Add(new PSNoteProperty("LocalSMOVersion", localSmo));
            output.Properties.Add(new PSNoteProperty("LocalDomainUser", localDomainUser));
            output.Properties.Add(new PSNoteProperty("LocalRunAsAdmin", localRunAsAdmin));
            output.Properties.Add(new PSNoteProperty("LocalEdition", localEdition));
            WriteObject(output);
        }
    }

    /// <summary>PS member-access enumeration over a nested command's results: no items =
    /// null, one item = its property value, several = the per-item projection (null
    /// elements skipped).</summary>
    private static object? ProjectMember(List<PSObject> items, string name)
    {
        if (items.Count == 0)
            return null;
        if (items.Count == 1)
            return PsProperty.Get(items[0], name);
        List<object?> values = new List<object?>();
        foreach (PSObject item in items)
        {
            object? value = PsProperty.Get(item, name);
            if (value is not null)
                values.Add(value);
        }
        return values.ToArray();
    }

    /// <summary>PS: the SMO version segment of the loaded assembly FullName -
    /// ((...GetAssemblies() | Where FullName -like "Microsoft.SqlServer.SMO,*").FullName
    /// -Split ", ")[1].TrimStart("Version=").</summary>
    private static string? GetLoadedSmoVersion()
    {
        foreach (System.Reflection.Assembly assembly in AppDomain.CurrentDomain.GetAssemblies())
        {
            string? fullName;
            try { fullName = assembly.FullName; }
            catch { continue; }
            if (fullName is not null && fullName.StartsWith("Microsoft.SqlServer.SMO,", StringComparison.OrdinalIgnoreCase))
            {
                string[] parts = System.Text.RegularExpressions.Regex.Split(fullName, ", ");
                if (parts.Length > 1)
                    return parts[1].TrimStart('V', 'e', 'r', 's', 'i', 'o', 'n', '=');
                return null;
            }
        }
        return null;
    }

    /// <summary>PS interpolation-style text for property values ([string]$x - null renders
    /// empty).</summary>
    private static string PsToText(object? value)
    {
        if (value is null)
            return "";
        return PSObject.AsPSObject(value).ToString();
    }

    /// <summary>Hashtable key access the way the PS dot operator reads $PSVersionTable.</summary>
    private static object? GetTableEntry(object? table, string key)
    {
        if (PsAssignment.Unwrap(table) is System.Collections.IDictionary dictionary)
            return dictionary[key];
        return PsProperty.Get(table, key);
    }

    /// <summary>Detects the hop script's caught-error marker (outcome-as-data).</summary>
    private static ErrorRecord? ExtractCaughtError(PSObject? item)
    {
        if (item?.BaseObject is PSCustomObject)
        {
            PSPropertyInfo? marker = item.Properties["__dbatoolsCaughtError"];
            if (marker?.Value is not null)
                return PsAssignment.Unwrap(marker.Value) as ErrorRecord;
        }
        return null;
    }

    private const string ResolveScript = """
param($__computerName, $__credential)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($__computerName, $__credential)
    try {
        Resolve-DbaNetworkName -ComputerName $__computerName -Credential $__credential -EnableException 3>&1
    } catch {
        [PSCustomObject]@{ __dbatoolsCaughtError = $PSItem }
    }
} $__computerName $__credential
""";

    private const string RemotingScript = """
param($__computerName, $__credential)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($__computerName, $__credential)
    try {
        $null = Invoke-Command2 -ComputerName $__computerName -Credential $__credential -ScriptBlock { Get-ChildItem } -ErrorAction Stop
    } catch {
        [PSCustomObject]@{ __dbatoolsCaughtError = $PSItem }
    }
} $__computerName $__credential
""";

    private const string ConnectScript = """
param($__instance, $__sqlCredential)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($__instance, $__sqlCredential)
    try {
        Connect-DbaInstance -SqlInstance $__instance -SqlCredential $__sqlCredential 3>&1
    } catch {
        [PSCustomObject]@{ __dbatoolsCaughtError = $PSItem }
    }
} $__instance $__sqlCredential
""";

    private const string TcpPortScript = """
param($__instance, $__sqlCredential, $__credential)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($__instance, $__sqlCredential, $__credential)
    try {
        Get-DbaTcpPort -SqlInstance $__instance -SqlCredential $__sqlCredential -Credential $__credential -EnableException 3>&1
    } catch {
        [PSCustomObject]@{ __dbatoolsCaughtError = $PSItem }
    }
} $__instance $__sqlCredential $__credential
""";

    private const string AuthSchemeScript = """
param($__server)
$__dbatoolsModule = Get-Module -Name dbatools | Where-Object ModuleType -eq "Script" | Select-Object -First 1
& $__dbatoolsModule {
    param($__server)
    try {
        Test-DbaConnectionAuthScheme -SqlInstance $__server -EnableException 3>&1
    } catch {
        [PSCustomObject]@{ __dbatoolsCaughtError = $PSItem }
    }
} $__server
""";
}
