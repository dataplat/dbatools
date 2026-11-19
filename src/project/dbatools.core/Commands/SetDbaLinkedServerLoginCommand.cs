#nullable enable

using System;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Alters linked server login mappings (the local-login to remote-login mapping on a linked
/// server). NEW designed command - no PS ancestor, pure C#, no hop. Surface pinned by
/// migration/designed/Set-DbaLinkedServerLogin.json (signed 2026-07-21).
///
/// SMO. LinkedServerLogin.Alter() (Smo/LinkedServerLoginBase.cs:162). ScriptAlter simply
/// delegates to ScriptCreate under the comment "alter is the same as create, because the same
/// stored proc is invoked" (:165-171), so an Alter re-runs sp_addlinkedsrvlogin, and ScriptCreate
/// emits @useself only when Impersonate is DIRTY and @rmtuser/@rmtpassword only when RemoteUser
/// is dirty. Impersonate and RemoteUser are the only alterable properties; Name is
/// ReadOnlyAfterCreation (:40), so -LocalLogin identifies the mapping and can never rename it -
/// there is deliberately no -NewName.
///
/// THE PASSWORD IS A METHOD, NOT A PROPERTY. SetRemotePassword writes a private field with no
/// getter (:33, :173, :180), so the secret is structurally write-only and can never be echoed in
/// output, verbose or WhatIf text (new-commands.md 1.4). This command calls the SecureString
/// overload (:180) directly rather than flattening through ConvertFrom-SecurePass the way the
/// retired private/retired/New-DbaLinkedServerLogin.ps1:143 does - a new command has no legacy
/// reason to materialise the secret as a managed string. Both overloads force-dirty Impersonate
/// AND RemoteUser (:176-177, :183-184), which is exactly what makes ScriptCreate's dirty-gated
/// clauses emit; this command relies on that and must NOT re-dirty them by hand.
///
/// -Impersonate is applied only when BOUND, so -Impersonate:$false switches a mapping off
/// self-credential and an omitted -Impersonate leaves it alone. The retired New- sets Impersonate
/// unconditionally (:146); copying that here would silently clear Impersonate on every Set- that
/// omitted the switch. That is the single most likely regression in this command and it has its
/// own test.
///
/// CROSS-RECORD HAZARD. GetDbaLinkedServerLoginCommand carries a deliberate stale-$ls sentinel
/// (__getLslCarry) reproducing a legacy defect. This command resolves the parent LinkedServer per
/// record and must not reproduce that carry; the multi-record piped test proves it.
/// </summary>
[Cmdlet(VerbsCommon.Set, "DbaLinkedServerLogin", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
[OutputType(typeof(Microsoft.SqlServer.Management.Smo.LinkedServerLogin))]
public sealed class SetDbaLinkedServerLoginCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public override DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Alternative credential for the target instances.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>The linked server(s) holding the login mapping to alter.</summary>
    [Parameter(Position = 2)]
    public string[]? LinkedServer { get; set; }

    /// <summary>The local login that identifies the mapping. Never renamed - Name is read-only after creation.</summary>
    [Parameter(Position = 3)]
    public string? LocalLogin { get; set; }

    /// <summary>The remote user the local login maps to.</summary>
    [Parameter(Position = 4)]
    public string? RemoteUser { get; set; }

    /// <summary>The remote user's password. Write-only: never emitted, logged or echoed.</summary>
    [Parameter(Position = 5)]
    public System.Security.SecureString? RemoteUserPassword { get; set; }

    /// <summary>SMO LinkedServerLogin object(s) from Get-DbaLinkedServerLogin.</summary>
    [Parameter(ValueFromPipeline = true, Position = 6)]
    public Microsoft.SqlServer.Management.Smo.LinkedServerLogin[]? InputObject { get; set; }

    /// <summary>Map local logins to connect to the remote server using their own credentials.</summary>
    [Parameter]
    public SwitchParameter Impersonate { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        // Either/or duality with no parameter sets (new-commands.md 1.2). The check lives here
        // rather than in BeginProcessing because a pipeline-bound InputObject does not appear in
        // BoundParameters until ProcessRecord - a Begin-time check would false-fail pure pipeline
        // usage. Behaviour is identical when neither is supplied: one ProcessRecord fires and the
        // check trips. Noted as a spec-wording correction in the row Evidence.
        if (!TestBound(nameof(SqlInstance), nameof(InputObject)))
        {
            StopFunction("You must supply either -SqlInstance or an Input Object");
            return;
        }

        // Feeder 1: resolve mappings from -SqlInstance. -LinkedServer and -LocalLogin identify
        // the mapping here (mirroring private/retired/New-DbaLinkedServerLogin.ps1:113-121); they
        // are NOT required on the pipeline path, where the piped LinkedServerLogin IS the mapping.
        if (TestBound(nameof(SqlInstance)))
        {
            if (LinkedServer is null || LinkedServer.Length == 0)
            {
                StopFunction("LinkedServer is required when SqlInstance is specified");
                return;
            }

            if (String.IsNullOrEmpty(LocalLogin))
            {
                StopFunction("LocalLogin is required when SqlInstance is specified");
                return;
            }

            foreach (DbaInstanceParameter instance in SqlInstance ?? Array.Empty<DbaInstanceParameter>())
            {
                Server? server = ConnectInstance(instance, "Failure");
                if (server is null)
                {
                    continue;
                }

                foreach (Microsoft.SqlServer.Management.Smo.LinkedServerLogin login in ResolveLogins(server))
                {
                    ProcessLogin(login);
                }
            }
        }

        // Feeder 2: LinkedServerLogin objects piped from Get-DbaLinkedServerLogin. The parent
        // chain is resolved PER RECORD (login.Parent = LinkedServer, .Parent = Server) - never
        // carried across records, and never reconnected.
        foreach (Microsoft.SqlServer.Management.Smo.LinkedServerLogin login in InputObject ?? Array.Empty<Microsoft.SqlServer.Management.Smo.LinkedServerLogin>())
        {
            ProcessLogin(login);
        }
    }

    // One worker, two feeders (new-commands.md 1.2).
    private void ProcessLogin(Microsoft.SqlServer.Management.Smo.LinkedServerLogin login)
    {
        Microsoft.SqlServer.Management.Smo.LinkedServer? parent = login.Parent;
        if (parent is null)
        {
            StopFunction(String.Format("Linked server login {0} has no parent linked server", login.Name),
                target: login, category: ErrorCategory.InvalidData, continueLoop: true);
            return;
        }

        Server? server = parent.Parent;
        if (server is null)
        {
            StopFunction(String.Format("Linked server {0} has no parent server", parent.Name),
                target: login, category: ErrorCategory.InvalidData, continueLoop: true);
            return;
        }

        // ShouldProcess strings are VERBATIM from the signed spec's shouldProcessTargets and are
        // immutable once the tests merge. The secret never appears here.
        string target = Dataplat.Dbatools.Connection.SmoServerExtensions.GetDomainInstanceName(server);
        string action = String.Format("Altering linked server login {0} on linked server {1}", login.Name, parent.Name);
        if (!ShouldProcess(target, action))
        {
            return;
        }

        try
        {
            // Apply ONLY explicitly-bound options - unbound must mean "leave unchanged".
            if (TestBound(nameof(RemoteUser)))
            {
                login.RemoteUser = RemoteUser;
            }

            if (TestBound(nameof(Impersonate)))
            {
                login.Impersonate = Impersonate.ToBool();
            }

            // STATE PRESERVATION - the load-bearing subtlety of this command, proven by a red
            // integration test before this block existed. Alter() re-runs sp_addlinkedsrvlogin
            // (LinkedServerLoginBase.cs:165-171), and ScriptCreate emits @useself ONLY when
            // Impersonate is dirty and @rmtuser/@rmtpassword ONLY when RemoteUser is dirty. The
            // stored proc's SERVER-SIDE defaults are @useself = TRUE and @rmtuser = NULL, so an
            // omitted clause does NOT mean "leave alone" - it means "reset". Changing RemoteUser
            // alone therefore omitted @useself, the server defaulted it to TRUE, and the mapping
            // silently flipped to self-credential with RemoteUser blanked.
            // Re-asserting the CURRENT value makes the property dirty without changing it
            // (propertiesCollection.cs:357-370 SetValueFromUser calls SetDirty unconditionally on
            // the non-notifying path), so the emitted proc call restates the full existing state.
            if (!TestBound(nameof(Impersonate)))
            {
                login.Impersonate = login.Impersonate;
            }

            // Null-guarded: the property setter refuses null outright (SetValueWithConsistencyCheck
            // throws ArgumentNullException when allowNull is false), and a self-credential mapping
            // has nothing to restate anyway.
            if (!TestBound(nameof(RemoteUser)) && login.RemoteUser is not null)
            {
                login.RemoteUser = login.RemoteUser;
            }

            // The password is the one piece of state that CANNOT be preserved: it lives in a
            // private write-only field (LinkedServerLoginBase.cs:33) with no getter, so when
            // @rmtuser is emitted without a caller-supplied password, @rmtpassword goes out NULL
            // and the stored remote password is cleared. That is inherent to sp_addlinkedsrvlogin,
            // not a choice this command can make - so it is surfaced rather than done silently.
            if (TestBound(nameof(RemoteUser)) && !TestBound(nameof(RemoteUserPassword)))
            {
                WriteMessage(Dataplat.Dbatools.Message.MessageLevel.Warning,
                    String.Format("Changing -RemoteUser without -RemoteUserPassword clears the stored remote password for {0} on linked server {1}, because sp_addlinkedsrvlogin restates the whole mapping and the existing password cannot be read back", login.Name, parent.Name),
                    target: login);
            }

            // SecureString overload (LinkedServerLoginBase.cs:180). This force-dirties Impersonate
            // and RemoteUser itself, which is what makes ScriptCreate emit @useself/@rmtuser/
            // @rmtpassword - do not re-dirty either property by hand.
            if (TestBound(nameof(RemoteUserPassword)))
            {
                login.SetRemotePassword(RemoteUserPassword);
            }

            login.Alter();
            login.Refresh();
        }
        catch (Exception ex)
        {
            StopFunction(String.Format("Failure altering linked server login {0} on {1}", login.Name, parent.Name),
                target: login,
                errorRecord: new ErrorRecord(ex, "dbatools_SetDbaLinkedServerLogin", ErrorCategory.InvalidOperation, login),
                continueLoop: true);
            return;
        }

        // Decorated exactly like Get-DbaLinkedServerLogin so Get -> Set -> Get composes.
        // Replace-then-add, never AddInstanceProperties: anything piped in from the getCounterpart
        // is ALREADY decorated and Properties.Add throws on a duplicate member name.
        PSObject wrapped = PSObject.AsPSObject(login);
        ReplaceNoteProperty(wrapped, "ComputerName", Dataplat.Dbatools.Connection.SmoServerExtensions.GetComputerName(server));
        ReplaceNoteProperty(wrapped, "InstanceName", server.ServiceName);
        ReplaceNoteProperty(wrapped, "SqlInstance", Dataplat.Dbatools.Connection.SmoServerExtensions.GetDomainInstanceName(server));
        OutputHelper.SetDefaultDisplayPropertySet(wrapped,
            "ComputerName", "InstanceName", "SqlInstance", "Name", "RemoteUser", "Impersonate");
        WriteObject(wrapped);
    }

    private static void ReplaceNoteProperty(PSObject wrapped, string name, object? value)
    {
        if (wrapped.Properties[name] is PSNoteProperty)
        {
            wrapped.Properties.Remove(name);
        }
        wrapped.Properties.Add(new PSNoteProperty(name, value));
    }

    // Not a lazy iterator ON PURPOSE: a requested-but-missing linked server or local login must be
    // REPORTED (warn + continue, terminating under -EnableException), never silently skipped.
    private List<Microsoft.SqlServer.Management.Smo.LinkedServerLogin> ResolveLogins(Server server)
    {
        List<Microsoft.SqlServer.Management.Smo.LinkedServerLogin> resolved = new();

        foreach (string linkedServerName in LinkedServer ?? Array.Empty<string>())
        {
            Microsoft.SqlServer.Management.Smo.LinkedServer? linkedServer = server.LinkedServers[linkedServerName];
            if (linkedServer is null)
            {
                StopFunction(String.Format("Linked server {0} does not exist on {1}", linkedServerName, server.Name),
                    target: linkedServerName, category: ErrorCategory.ObjectNotFound, continueLoop: true);
                continue;
            }

            Microsoft.SqlServer.Management.Smo.LinkedServerLogin? login = linkedServer.LinkedServerLogins[LocalLogin];
            if (login is null)
            {
                StopFunction(String.Format("Linked server login {0} does not exist on linked server {1} on {2}", LocalLogin, linkedServerName, server.Name),
                    target: LocalLogin, category: ErrorCategory.ObjectNotFound, continueLoop: true);
                continue;
            }

            resolved.Add(login);
        }

        return resolved;
    }
}
