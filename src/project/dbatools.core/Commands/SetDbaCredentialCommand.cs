#nullable enable

using System;
using System.Management.Automation;
using System.Security;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>
/// Alters an existing SQL Server credential in place - its Identity and/or its secret. NEW designed
/// command, no PS ancestor, pure C#, no hop. Completes the credential CRUD family (New-/Get-/Remove-/
/// Export-DbaCredential already exist; there was no Set-). Surface pinned by
/// migration/designed/Set-DbaCredential.json (signed gomanager 2026-07-22).
///
/// MODULE. The signed spec sets module dbatools.core, resolving the split its designNotes flagged for
/// sign-off: the whole family (Get-/New-/Remove-/Export-DbaCredential) lives in dbatools.core, so Set-
/// joins it there. The tracker cell still read dbatools.security (provisional attribution); the signed
/// spec is authoritative and the code follows it, same as the DbUser/DbRole rows.
///
/// SCOPE. Before this command the only way to change a credential's identity or secret was
/// drop-and-recreate. This replaces that with a single ALTER CREDENTIAL.
///
/// SMO. THE ALTERABLE SURFACE IS EXACTLY Identity AND THE SECRET, and they are structurally coupled.
/// Smo/CredentialBase.cs:296-330 CreateAlterScript is shared by CREATE and ALTER; it throws
/// PropertyNotSetException("Identity") when Identity is empty (:299-302) then emits
/// 'ALTER CREDENTIAL &lt;name&gt; WITH IDENTITY = N''...''' UNCONDITIONALLY (:317-321), appending
/// ', SECRET = N''...''' only when the private secret field is non-null (:323-330). There is NO
/// secret-only ALTER path: plain Alter() (:109) scripts only when IsObjectDirty() (:176) and the secret
/// is NOT a tracked property (private field :358), so setting only the secret would emit NOTHING. The
/// Alter(string, SecureString) overload (:151) works precisely because it assigns Identity FIRST
/// (:163), dirtying the object, then the secret (:164). Overload selection is therefore required for
/// correctness, not style. This command always routes an alter through that single overload with
/// identityToUse = -Identity when bound else the fetched credential's current Identity, and the
/// SecureString = -SecurePassword when bound else null. That one call covers all three cases:
/// identity-only (secret null -&gt; IDENTITY clause only), secret-only (IDENTITY re-asserted at its
/// current value + SECRET), and both.
///
/// THE SECRET IS NOT A PROPERTY. Smo/CredentialBase.cs:358 declares 'private SqlSecureString secret;'
/// with no public accessor and :329 nulls it right after scripting, so it is structurally impossible to
/// emit in output, verbose or WhatIf text - new-commands.md 1.4 satisfied by construction. The cmdlet
/// uses the SecureString overload, never the string overload (:128). SECURITY CAVEAT documented in help:
/// SMO itself notes at :354-357 that the SecureString protection is shallow - the secret is interpolated
/// as clear text into the T-SQL batch (:325-327) and is visible to any server-side trace or Extended
/// Events capture. Nothing at the cmdlet layer can change this.
///
/// PROVIDERNAME AND MAPPEDCLASSTYPE ARE NOT ON THE SURFACE. Smo/CredentialBase.cs:34-37
/// GetNonAlterableProperties() returns exactly { "ProviderName", "MappedClassType" } and
/// Smo/SqlSmoObject.cs throws PropNotModifiable if either is dirty at Alter() time; both are scripted
/// only on create (:332 'if (create &amp;&amp; ServerVersion.Major &gt;= 10)'). New-DbaCredential exposes
/// both; this command deliberately does not, and the help documents drop-and-recreate for a provider
/// change.
///
/// SELECTION and DUALITY. Either -SqlInstance (+ -Credential naming which credential(s) to alter) or
/// -InputObject, no parameter sets (new-commands.md 1.2). -Credential is REQUIRED on the -SqlInstance
/// path (mirroring Set-DbaCustomError requiring -MessageID): without a selector there is nothing to
/// alter, and defaulting to "all credentials" would apply one -Identity to every credential on the
/// instance - a footgun. -Identity here is the NEW value being written (singular String, alias
/// CredentialIdentity), following New-DbaCredential; that differs from Remove-DbaCredential where
/// -Identity is a filter - a Set- cannot use one name for both meanings and matching the verb that also
/// WRITES Identity is the less surprising choice (spec designNotes).
///
/// OUTPUT. Re-emits the refreshed Smo.Credential decorated exactly like Get-DbaCredential
/// (GetDbaCredentialCommand.cs decorates in its PS hop: ComputerName/InstanceName/SqlInstance +
/// default view ComputerName, InstanceName, SqlInstance, ID, Name, Identity, MappedClassType,
/// ProviderName) so Get -&gt; Set -&gt; Get composes. Replace-then-add so a piped, already-decorated
/// object does not throw on Properties.Add.
///
/// CONFIRMIMPACT Medium, matching New-DbaCredential: rotating a credential's identity or secret can
/// break every consumer (backup-to-URL, EKM providers, proxies), which is more than a Low toggle, but
/// it destroys no object so it is not Remove-'s High.
/// </summary>
[Cmdlet(VerbsCommon.Set, "DbaCredential", SupportsShouldProcess = true, ConfirmImpact = ConfirmImpact.Medium)]
[OutputType(typeof(Credential))]
public sealed class SetDbaCredentialCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Position = 0)]
    public override DbaInstanceParameter[]? SqlInstance { get; set; }

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>The name(s) of the credential(s) to alter on the -SqlInstance path.</summary>
    [Parameter(Position = 2)]
    public string[]? Credential { get; set; }

    /// <summary>The new identity to write. Singular; when omitted the current identity is retained.</summary>
    [Parameter(Position = 3)]
    [Alias("CredentialIdentity")]
    public string? Identity { get; set; }

    /// <summary>The new secret as a SecureString. Write-only; never surfaced in output, verbose or WhatIf.</summary>
    [Parameter(Position = 4)]
    [Alias("Password")]
    public SecureString? SecurePassword { get; set; }

    /// <summary>SMO Credential object(s), typically from Get-DbaCredential.</summary>
    [Parameter(ValueFromPipeline = true, Position = 5)]
    public Credential[]? InputObject { get; set; }

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
            // -Credential selects the credential(s) on the -SqlInstance path; without it there is
            // nothing to alter, and altering every credential to one identity is a footgun.
            if (!TestBound(nameof(Credential)))
            {
                StopFunction("You must supply -Credential when connecting with -SqlInstance");
                return;
            }

            foreach (DbaInstanceParameter instance in SqlInstance ?? Array.Empty<DbaInstanceParameter>())
            {
                Server? server = ConnectInstance(instance, "Failure");
                if (server is null)
                {
                    continue;
                }

                foreach (Credential credential in ResolveCredentials(server))
                {
                    ProcessCredential(credential, server);
                }
            }
        }

        // Feeder 2: Credential objects piped from Get-DbaCredential. The parent server is resolved
        // PER RECORD (credential.Parent) - never carried across records, never reconnected.
        foreach (Credential credential in InputObject ?? Array.Empty<Credential>())
        {
            Server? server = credential.Parent;
            if (server is null)
            {
                StopFunction(String.Format("Credential {0} has no parent server", credential.Name),
                    target: credential, category: ErrorCategory.InvalidData, continueLoop: true);
                continue;
            }

            ProcessCredential(credential, server);
        }
    }

    // Selects the credentials named by -Credential on the -SqlInstance path (case-insensitive exact
    // name match, mirroring Get-DbaCredential's '$Credential -contains $_.Name'). A name that matches
    // nothing is a graceful Stop-Function -Continue so a typo does not silently do nothing.
    private System.Collections.Generic.IEnumerable<Credential> ResolveCredentials(Server server)
    {
        string target = SmoServerExtensions.GetDomainInstanceName(server);
        string[] names = Credential ?? Array.Empty<string>();

        foreach (string name in names)
        {
            bool found = false;
            foreach (Credential credential in server.Credentials)
            {
                if (String.Equals(credential.Name, name, StringComparison.OrdinalIgnoreCase))
                {
                    found = true;
                    yield return credential;
                    break;
                }
            }

            if (!found)
            {
                StopFunction(String.Format("Credential {0} does not exist on {1}", name, target),
                    target: server, category: ErrorCategory.ObjectNotFound, continueLoop: true);
            }
        }
    }

    // One worker, two feeders (new-commands.md 1.2). Alters only when -Identity or -SecurePassword is
    // bound, routing through the single SMO overload that dirties Identity so ScriptAlter emits.
    private void ProcessCredential(Credential credential, Server server)
    {
        string target = SmoServerExtensions.GetDomainInstanceName(server);

        bool alterRequested = TestBound(nameof(Identity)) || TestBound(nameof(SecurePassword));

        if (alterRequested)
        {
            // ShouldProcess string is VERBATIM from the signed spec's shouldProcessTargets and is
            // immutable once the tests merge.
            string action = String.Format("Altering credential {0}", credential.Name);
            if (ShouldProcess(target, action))
            {
                try
                {
                    // identityToUse = the new identity when bound, else the credential's current
                    // identity (so a -SecurePassword-only call re-asserts identity to dirty the
                    // object). SecurePassword is null when unbound -> only the IDENTITY clause emits.
                    string identityToUse = TestBound(nameof(Identity)) ? Identity! : credential.Identity;
                    credential.Alter(identityToUse, SecurePassword);
                }
                catch (Exception ex)
                {
                    StopFunction(String.Format("Failure altering credential {0} on {1}", credential.Name, target),
                        target: credential,
                        errorRecord: new ErrorRecord(ex, "dbatools_SetDbaCredential", ErrorCategory.InvalidOperation, credential),
                        continueLoop: true);
                    return;
                }
            }
        }

        try
        {
            credential.Refresh();
        }
        catch (Exception)
        {
            // A refresh failure must not lose the object the caller just successfully altered.
        }

        WriteCredential(credential, server);
    }

    // Decorated exactly like Get-DbaCredential. Replace-then-add so a piped, already-decorated object
    // does not throw on Properties.Add.
    private void WriteCredential(Credential credential, Server server)
    {
        PSObject wrapped = PSObject.AsPSObject(credential);
        ReplaceNoteProperty(wrapped, "ComputerName", SmoServerExtensions.GetComputerName(server));
        ReplaceNoteProperty(wrapped, "InstanceName", server.ServiceName);
        ReplaceNoteProperty(wrapped, "SqlInstance", SmoServerExtensions.GetDomainInstanceName(server));

        OutputHelper.SetDefaultDisplayPropertySet(wrapped,
            "ComputerName", "InstanceName", "SqlInstance", "ID", "Name", "Identity", "MappedClassType", "ProviderName");

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
