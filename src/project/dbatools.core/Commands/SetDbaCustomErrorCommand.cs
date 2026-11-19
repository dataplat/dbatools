#nullable enable

using System;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;
using SmoLanguage = Microsoft.SqlServer.Management.Smo.Language;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Alters an existing user-defined error message (sys.messages) in place. NEW designed command -
/// no PS ancestor, pure C#, no hop. Completes the custom-error CRUD family (New-/Get-/Remove-/
/// Copy-DbaCustomError already exist; there was no Set-). Surface pinned by
/// migration/designed/Set-DbaCustomError.json (signed 2026-07-22).
///
/// SCOPE. Before this command, the only way to change a message was drop-and-recreate
/// (private/retired/New-DbaCustomError.ps1 shows the round trip in its own help). This replaces
/// that with a single ALTER.
///
/// SMO. UserDefinedMessage.Alter() re-issues sp_addmessage ... @replace='REPLACE' keyed by
/// @msgnum/@lang from the object key, and adds the ALTER statement ONLY when Severity, Text or
/// IsLogged is dirty (Properties.ArePropertiesDirty over exactly those three). So the ALTERABLE
/// SET IS EXACTLY THREE PROPERTIES and Alter() with nothing dirty is a genuine no-op. No other
/// property can be altered.
///
/// MessageID and Language are the composite KEY and are read-only after creation (both [SfcKey],
/// ReadOnlyAfterCreation). They are SELECTORS here, never things this command can change -
/// re-keying a message still requires drop-and-recreate. There is no -NewMessageID and no
/// -NewLanguage. -MessageText maps to the SMO Text property (max 255) and -WithLog to IsLogged,
/// keeping New-DbaCustomError's vocabulary rather than SMO's.
///
/// SWITCHES, per dbatools CLAUDE.md (use [switch], never [bool]). -WithLog is a switch and, like
/// Severity/MessageText, is applied ONLY when BOUND; an unbound parameter leaves that property
/// untouched, so a caller changing only the text does not reset severity or the log flag. The
/// explicit -WithLog:$false form turns logging off.
///
/// DUALITY. Either -SqlInstance (+ -MessageID, optional -Language) or -InputObject, no parameter
/// sets (new-commands.md 1.2). The check lives in ProcessRecord because a pipeline-bound
/// InputObject is not in BoundParameters until then.
///
/// LANGUAGE RESOLUTION deviates from the spec's designNotes and it is recorded here: the spec
/// describes a sys.syslanguages query with SqlParameter, but this resolves -Language against the
/// server's own SMO language collection (Server.Languages) instead - SMO-first per CLAUDE.md, and
/// it concatenates no user value into any T-SQL at all. Behaviour is identical: a language the
/// instance does not have installed produces a graceful Stop-Function. The selected message is
/// matched by ID plus the resolved language's Name or Alias, which round-trips regardless of which
/// string SMO stores on UserDefinedMessage.Language.
///
/// SEVERITY IS NOT PER-LANGUAGE. SQL Server requires every localized version of a message to share
/// one severity, so a -Severity change is observable on all languages of that message ID. The help
/// states this; the command does not try to hide it.
///
/// OUTPUT. Re-emits the refreshed Smo.UserDefinedMessage decorated exactly like Get-DbaCustomError
/// (GetDbaCustomErrorCommand.cs:43-56 replace-then-add, chosen because these SMO objects may
/// already carry the instance notes and Properties.Add throws on a duplicate). Default view
/// ComputerName, InstanceName, SqlInstance, ID, Text, LanguageID, Language.
/// </summary>
[Cmdlet(VerbsCommon.Set, "DbaCustomError", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Low)]
[OutputType(typeof(UserDefinedMessage))]
public sealed class SetDbaCustomErrorCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public override DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>The message ID (50001-2147483647) selecting which custom error to alter. Read-only key, never changed.</summary>
    [Parameter(Position = 2)]
    [ValidateRange(50001, 2147483647)]
    public int MessageID { get; set; }

    /// <summary>New severity level (1-25). Shared across every language of the message ID.</summary>
    [Parameter(Position = 3)]
    [ValidateRange(1, 25)]
    public int Severity { get; set; }

    /// <summary>New message text (max 255 characters), mapped to the SMO Text property.</summary>
    [Parameter(Position = 4)]
    [ValidateLength(0, 255)]
    public string? MessageText { get; set; }

    /// <summary>The language (sys.syslanguages Name or Alias) selecting which localized message to alter. Read-only key. Defaults to English.</summary>
    [Parameter(Position = 5)]
    public string? Language { get; set; }

    /// <summary>SMO UserDefinedMessage object(s), typically from Get-DbaCustomError.</summary>
    [Parameter(ValueFromPipeline = true, Position = 6)]
    public UserDefinedMessage[]? InputObject { get; set; }

    /// <summary>Set the log-to-eventlog flag (IsLogged). Bound-only; -WithLog:$false turns it off, unbound leaves it alone.</summary>
    [Parameter]
    public SwitchParameter WithLog { get; set; }

    // EnableException is inherited from DbaBaseCmdlet - never redeclared.

    protected override void ProcessRecord()
    {
        if (Interrupted)
        {
            return;
        }

        // Duality, no parameter sets (new-commands.md 1.2). Checked here, not in BeginProcessing,
        // because a pipeline-bound InputObject is not in BoundParameters until ProcessRecord.
        if (!TestBound(nameof(SqlInstance), nameof(InputObject)))
        {
            StopFunction("You must supply either -SqlInstance or an Input Object");
            return;
        }

        if (TestBound(nameof(SqlInstance)))
        {
            // -MessageID selects the message on the -SqlInstance path; without it there is nothing to alter.
            if (!TestBound(nameof(MessageID)))
            {
                StopFunction("You must supply -MessageID when connecting with -SqlInstance");
                return;
            }

            foreach (DbaInstanceParameter instance in SqlInstance ?? Array.Empty<DbaInstanceParameter>())
            {
                // Custom errors (sys.messages) are not supported on Azure SQL Database.
                Server? server = ConnectInstance(instance, "Failure", azureUnsupported: true);
                if (server is null)
                {
                    continue;
                }

                UserDefinedMessage? message = ResolveMessage(server);
                if (message is null)
                {
                    continue;
                }

                ProcessMessage(message, server);
            }
        }

        // Feeder 2: UserDefinedMessage objects piped from Get-DbaCustomError. The parent server is
        // resolved PER RECORD (message.Parent) - never carried across records, never reconnected.
        foreach (UserDefinedMessage message in InputObject ?? Array.Empty<UserDefinedMessage>())
        {
            Server? server = message.Parent;
            if (server is null)
            {
                StopFunction(String.Format("Custom error {0} has no parent server", message.ID),
                    target: message, category: ErrorCategory.InvalidData, continueLoop: true);
                continue;
            }

            ProcessMessage(message, server);
        }
    }

    // Selects the UserDefinedMessage on the -SqlInstance path by ID + resolved language. -Language
    // defaults to English (matching New-DbaCustomError). A language the instance does not have
    // installed, or a missing message, is a graceful Stop-Function -Continue.
    private UserDefinedMessage? ResolveMessage(Server server)
    {
        string target = SmoServerExtensions.GetDomainInstanceName(server);
        string requested = TestBound(nameof(Language)) ? Language! : "English";

        SmoLanguage? resolved = null;
        foreach (SmoLanguage language in server.Languages)
        {
            if (String.Equals(language.Name, requested, StringComparison.OrdinalIgnoreCase)
                || String.Equals(language.Alias, requested, StringComparison.OrdinalIgnoreCase))
            {
                resolved = language;
                break;
            }
        }

        if (resolved is null)
        {
            StopFunction(String.Format("{0} does not have the language {1} installed", target, requested),
                target: server, category: ErrorCategory.ObjectNotFound, continueLoop: true);
            return null;
        }

        foreach (UserDefinedMessage message in server.UserDefinedMessages)
        {
            if (message.ID == MessageID
                && (String.Equals(message.Language, resolved.Name, StringComparison.OrdinalIgnoreCase)
                    || String.Equals(message.Language, resolved.Alias, StringComparison.OrdinalIgnoreCase)))
            {
                return message;
            }
        }

        StopFunction(String.Format("Custom error {0} in language {1} does not exist on {2}", MessageID, requested, target),
            target: server, category: ErrorCategory.ObjectNotFound, continueLoop: true);
        return null;
    }

    // One worker, two feeders (new-commands.md 1.2). Applies only the bound properties, so the
    // dirty gate in Alter() decides whether any statement is emitted at all.
    private void ProcessMessage(UserDefinedMessage message, Server server)
    {
        string target = SmoServerExtensions.GetDomainInstanceName(server);

        bool alterRequested = TestBound(nameof(Severity)) || TestBound(nameof(MessageText)) || TestBound(nameof(WithLog));

        if (alterRequested)
        {
            // ShouldProcess string is VERBATIM from the signed spec's shouldProcessTargets and is
            // immutable once the tests merge.
            string action = String.Format("Altering custom error {0} in language {1}", message.ID, message.Language);
            if (ShouldProcess(target, action))
            {
                try
                {
                    if (TestBound(nameof(Severity)))
                    {
                        message.Severity = Severity;
                    }
                    if (TestBound(nameof(MessageText)))
                    {
                        message.Text = MessageText;
                    }
                    if (TestBound(nameof(WithLog)))
                    {
                        message.IsLogged = WithLog.ToBool();
                    }

                    message.Alter();
                }
                catch (Exception ex)
                {
                    StopFunction(String.Format("Failure altering custom error {0} on {1}", message.ID, target),
                        target: message,
                        errorRecord: new ErrorRecord(ex, "dbatools_SetDbaCustomError", ErrorCategory.InvalidOperation, message),
                        continueLoop: true);
                    return;
                }
            }
        }

        try
        {
            message.Refresh();
        }
        catch (Exception)
        {
            // A refresh failure must not lose the object the caller just successfully altered.
        }

        WriteCustomError(message, server);
    }

    // Decorated exactly like Get-DbaCustomError (GetDbaCustomErrorCommand.cs:43-56). Replace-then-add
    // so a piped, already-decorated object does not throw on Properties.Add.
    private void WriteCustomError(UserDefinedMessage message, Server server)
    {
        PSObject wrapped = PSObject.AsPSObject(message);
        ReplaceNoteProperty(wrapped, "ComputerName", SmoServerExtensions.GetComputerName(server));
        ReplaceNoteProperty(wrapped, "InstanceName", server.ServiceName);
        ReplaceNoteProperty(wrapped, "SqlInstance", SmoServerExtensions.GetDomainInstanceName(server));

        OutputHelper.SetDefaultDisplayPropertySet(wrapped,
            "ComputerName", "InstanceName", "SqlInstance", "ID", "Text", "LanguageID", "Language");

        WriteObject(wrapped);
    }

    private static void ReplaceNoteProperty(PSObject wrapped, string name, object? value)
    {
        if (wrapped.Properties[name] is not null)
        {
            wrapped.Properties.Remove(name);
        }
        wrapped.Properties.Add(new PSNoteProperty(name, value));
    }
}
