#nullable enable
#pragma warning disable CA1416 // Windows-only Active Directory expansion: System.DirectoryServices.AccountManagement, as in the source

using System;
using System.Collections;
using System.Collections.Generic;
using System.DirectoryServices.AccountManagement;
using System.Globalization;
using System.Management.Automation;
using System.Runtime.CompilerServices;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

// Port of public/Find-DbaLoginInGroup.ps1: the connection, the group selection and the recursive Active Directory
// expansion (the nested Get-AllLogins function) run here in C#. Kept from the source: Get-AllLogins emits the members
// of a group's nested groups before the group's own members; each branch of the recursion has its own copy of the
// list of groups already enumerated; its Stop-Function warns as Get-AllLogins, names the last member it saw (its
// own, else its caller's) and lets the command go on; a call that fails before setting its $subgroups walks its
// caller's, the variable PowerShell's dynamic scoping finds.
/// <summary>Discovers individual Active Directory users within Windows group logins on SQL Server instances.</summary>
[Cmdlet(VerbsCommon.Find, "DbaLoginInGroup")]
public sealed class FindDbaLoginInGroupCommand : DbaInstanceCmdlet
{
    private const string Helper = "Get-AllLogins";
    private const string NewObject = ".ctor";
    private static readonly string[] Defaults = { "SqlInstance", "Login", "DisplayName", "MemberOf", "ParentADGroupLogin" };

    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>Filters the expanded results to these login names.</summary>
    [Parameter(Position = 2)]
    public string[]? Login { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void BeginProcessing()
    {
        // PS: try { Add-Type -AssemblyName System.DirectoryServices.AccountManagement } catch {
        //     Stop-Function -Message "Failed to load Assembly needed" -ErrorRecord $_; return }
        try
        {
            LoadAccountManagement();
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            StopFunction("Failed to load Assembly needed", errorRecord: new ErrorRecord(failure, "ASSEMBLY_NOT_FOUND", ErrorCategory.InvalidOperation, null));
        }
    }

    protected override void ProcessRecord()
    {
        // PS: if (Test-FunctionInterrupt) { return }
        if (Interrupted)
            return;

        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            // PS: try { Connect-DbaInstance } catch { Stop-Function -Message "Failure" -Category ConnectionError -ErrorRecord $_ -Target $instance -Continue }
            // Correction azure-unsupported: Azure SQL Database has no Windows group logins to expand, so it is refused
            // as Connect-DbaInstance -AzureUnsupported refuses it.
            Server? server = ConnectInstance(instance, "Failure", azureUnsupported: true);
            if (server is null)
                continue;
            SearchInstance(server);
        }
    }

    private void SearchInstance(Server server)
    {
        // PS: $AdGroups = $server.Logins | Where-Object { $_.LoginType -eq "WindowsGroup" -and $_.Name -ne "BUILTIN\Administrators" -and $_.Name -notlike "*NT SERVICE*" }
        //     $AdGroups = $AdGroups | Where-Object Name -notlike "$($server.ComputerName)\*"
        WildcardPattern serviceAccounts = new("*NT SERVICE*", WildcardOptions.IgnoreCase);
        WildcardPattern localGroups = new(SmoServerExtensions.GetComputerName(server) + "\\*", WildcardOptions.IgnoreCase);
        List<Microsoft.SqlServer.Management.Smo.Login> groups = new();
        IEnumerator? enumerator = null;
        try
        {
            enumerator = LanguagePrimitives.GetEnumerator(server.Logins);
            while (enumerator is not null && enumerator.MoveNext())
            {
                Microsoft.SqlServer.Management.Smo.Login candidate = (Microsoft.SqlServer.Management.Smo.Login)enumerator.Current!;
                string name = candidate.Name ?? "";
                if (candidate.LoginType == LoginType.WindowsGroup &&
                    !String.Equals(name, "BUILTIN\\Administrators", StringComparison.OrdinalIgnoreCase) &&
                    !serviceAccounts.IsMatch(name) && !localGroups.IsMatch(name))
                    groups.Add(candidate);
            }
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            // caller-try: terminate -- the pipeline statement fault of the source; going on would search no groups and report nothing for the instance
            ThrowTerminatingError(EnumerationFault(failure, enumerator)); // style-ok: cs-raw-streams pipeline statement fault outside Stop-Function, as in the source
        }

        List<PSObject> found = new();
        foreach (Microsoft.SqlServer.Management.Smo.Login group in groups)
        {
            WriteMessage(MessageLevel.Verbose, "Looking at Group: " + PsText(group));
            // PS: $ADGroupOut += Get-AllLogins $AdGroup.Name -ParentADGroup $AdGroup.Name
            GetAllLogins(server, group.Name, new List<string>(), group.Name, null, new List<string>(), found);
        }

        List<PSObject> result = found;
        // PS: if (-not $Login) { $res = $ADGroupOut } else { ... }
        if (LanguagePrimitives.IsTrue(Login))
        {
            // PS: $res = $ADGroupOut | Where-Object { $Login -contains $_.Login }; if ($res.Length -eq 0) { continue }
            result = new List<PSObject>();
            foreach (PSObject row in found)
            {
                if (Contains(Login!, row.Properties["Login"].Value))
                    result.Add(row);
            }
            if (result.Count == 0)
                return;
        }

        // PS: Select-DefaultView -InputObject $res -Property SqlInstance, Login, DisplayName, MemberOf, ParentADGroupLogin
        foreach (PSObject row in result)
        {
            OutputHelper.SetDefaultDisplayPropertySet(row, Defaults);
            WriteObject(row);
        }
    }

    // PS: function Get-AllLogins { param ([string]$ADGroup, [string[]]$discard, [string]$ParentADGroup) }. Its
    // output, the members of its nested groups and then its own members, is appended to sink. callerMember and
    // callerSubgroups are the $member and $subgroups of its caller's scope, which it reads while it has none of its own.
    private void GetAllLogins(Server server, string adGroup, List<string> discard, string parentAdGroup, Principal? callerMember, List<string> callerSubgroups, List<PSObject> sink)
    {
        List<PSObject> output = new();
        List<string> subgroups = callerSubgroups;
        Principal? member = callerMember;
        IEnumerator? members = null;
        string? call = NewObject; // The .NET call under way; null while the source's foreach and property reads run.
        try
        {
            string domain = adGroup.Split('\\')[0];
            PrincipalContext ads = new(ContextType.Domain, domain);
            call = "FindByIdentity";
            GroupPrincipal? group = GroupPrincipal.FindByIdentity(ads, adGroup);
            subgroups = new List<string>();
            call = null;
            // PS: foreach ($member in $group.Members): a null $group has no members to walk.
            members = group is null ? null : LanguagePrimitives.GetEnumerator(Read("Members", () => group!.Members));
            while (members is not null && members.MoveNext())
            {
                Principal current = (Principal)members.Current!;
                member = current;
                string memberDomain = current.Context.Name;
                if (String.Equals(Read("StructuralObjectClass", () => current.StructuralObjectClass), "group", StringComparison.OrdinalIgnoreCase))
                {
                    string fullName = memberDomain + "\\" + Read("SamAccountName", () => current.SamAccountName);
                    if (Contains(discard, fullName))
                    {
                        WriteAttributedMessage(Helper, MessageLevel.Verbose, "skipping " + fullName + ", already enumerated");
                        continue;
                    }
                    subgroups.Add(fullName);
                }
                else
                {
                    // The source's [PSCustomObject] puts SqlInstance first, then InstanceName and ComputerName.
                    PSObject row = new();
                    row.Properties.Add(new PSNoteProperty("SqlInstance", server.Name)); // style-ok: cs-output-props the pinned [PSCustomObject] property order
                    row.Properties.Add(new PSNoteProperty("InstanceName", server.ServiceName)); // style-ok: cs-output-props the pinned [PSCustomObject] property order
                    row.Properties.Add(new PSNoteProperty("ComputerName", SmoServerExtensions.GetComputerName(server))); // style-ok: cs-output-props the pinned [PSCustomObject] property order
                    row.Properties.Add(new PSNoteProperty("Login", memberDomain + "\\" + Read("SamAccountName", () => current.SamAccountName)));
                    row.Properties.Add(new PSNoteProperty("DisplayName", Read("DisplayName", () => current.DisplayName)));
                    row.Properties.Add(new PSNoteProperty("MemberOf", adGroup));
                    row.Properties.Add(new PSNoteProperty("ParentADGroupLogin", parentAdGroup));
                    output.Add(row);
                }
            }
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            // PS: Stop-Function -Message "Failed to connect to Group: $member." -Target $member -ErrorRecord $_
            // The helper's Stop-Function has no -Continue: it warns, the helper goes on to its nested groups and the command to the next group.
            StopAttributedFunction(Helper, "Failed to connect to Group: " + PsText(member) + ".", target: member,
                errorRecord: CaughtRecord(failure, call, members), interruptCallerScope: false);
        }

        // PS: $discard += $ADGroup; foreach ($gr in $subgroups) { if ($gr -notin $discard) { $discard += $gr; ...; Get-AllLogins ... } }
        List<string> seen = new(discard) { adGroup };
        foreach (string nested in subgroups)
        {
            if (Contains(seen, nested))
                continue;
            seen.Add(nested);
            WriteAttributedMessage(Helper, MessageLevel.Verbose, "Looking at " + nested + ", recursively.");
            GetAllLogins(server, nested, new List<string>(seen), parentAdGroup, member, subgroups, sink);
        }

        // PS: end { $output }
        sink.AddRange(output);
    }

    // Referencing the type loads System.DirectoryServices.AccountManagement, as Add-Type -AssemblyName does.
    [MethodImpl(MethodImplOptions.NoInlining)]
    private static void LoadAccountManagement()
    {
        GC.KeepAlive(typeof(PrincipalContext).Assembly);
    }

    // PS: -contains and -in compare case-insensitively.
    private static bool Contains(IEnumerable<string> values, object? candidate)
    {
        foreach (string value in values)
        {
            if (LanguagePrimitives.Equals(value, candidate, true, CultureInfo.InvariantCulture))
                return true;
        }
        return false;
    }

    // PS: a property read that throws is 'Exception getting "Name": "message"'.
    private static T Read<T>(string property, Func<T> getter)
    {
        try
        {
            return getter();
        }
        catch (Exception failure) when (failure is not PipelineStoppedException)
        {
            throw new GetValueInvocationException(String.Format(CultureInfo.InvariantCulture,
                "Exception getting \"{0}\": \"{1}\"", property, failure.Message), failure);
        }
    }

    // The record the source's catch sees: the engine's when the failure carries one, New-Object's for the constructor,
    // a method call's for FindByIdentity, and otherwise the foreach's for the member enumeration.
    private static ErrorRecord CaughtRecord(Exception failure, string? call, IEnumerator? members)
    {
        if (failure is IContainsErrorRecord container && container.ErrorRecord is not null)
            return new ErrorRecord(container.ErrorRecord, failure);
        if (call is null)
            return EnumerationFault(failure, members);
        MethodInvocationException invocation = new(String.Format(CultureInfo.InvariantCulture,
            "Exception calling \"{0}\" with \"2\" argument(s): \"{1}\"", call, failure.Message), failure);
        return call == NewObject
            ? new ErrorRecord(invocation, "ConstructorInvokedThrowException", ErrorCategory.InvalidOperation, null)
            : new ErrorRecord(invocation, failure.GetType().Name, ErrorCategory.NotSpecified, null);
    }

    // The engine's record when the failure carries one (ExceptionInGetEnumerator); otherwise the record a failing
    // MoveNext gives (BadEnumeration, InvalidOperation, the enumerator as target).
    private static ErrorRecord EnumerationFault(Exception failure, IEnumerator? enumerator)
    {
        if (failure is IContainsErrorRecord container && container.ErrorRecord is not null)
            return new ErrorRecord(container.ErrorRecord, failure);
        RuntimeException fault = new(String.Format(CultureInfo.InvariantCulture,
            "An error occurred while enumerating through a collection: {0}.", failure.Message), failure);
        return new ErrorRecord(fault, "BadEnumeration", ErrorCategory.InvalidOperation, enumerator);
    }

    /// <summary>PS string interpolation: invariant culture.</summary>
    private static string PsText(object? value)
    {
        if (value is null)
            return "";
        return (string)LanguagePrimitives.ConvertTo(value, typeof(string), CultureInfo.InvariantCulture);
    }
}
