#nullable enable

using System;
using System.Collections.Generic;
using System.Management.Automation;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;
using SmoDatabase = Microsoft.SqlServer.Management.Smo.Database;

namespace Dataplat.Dbatools.Commands;

// Finds database users whose login is missing, directly through SMO (port of public/Get-DbaDbOrphanUser.ps1).
/// <summary>Get orphaned users.</summary>
[Cmdlet(VerbsCommon.Get, "DbaDbOrphanUser")]
public sealed class GetDbaDbOrphanUserCommand : DbaInstanceCmdlet
{
    /// <summary>The target SQL Server instance or instances.</summary>
    [Parameter(Mandatory = true, ValueFromPipeline = true, Position = 0)]
    public override DbaInstanceParameter[] SqlInstance { get; set; } = null!;

    /// <summary>Login to the target instance using alternative credentials.</summary>
    [Parameter(Position = 1)]
    public override PSCredential? SqlCredential { get; set; }

    /// <summary>The database(s) to check.</summary>
    [Parameter(Position = 2)]
    public object[]? Database { get; set; }

    /// <summary>The database(s) to exclude.</summary>
    [Parameter(Position = 3)]
    public object[]? ExcludeDatabase { get; set; }

    protected override void ProcessRecord()
    {
        foreach (DbaInstanceParameter instance in SqlInstance)
        {
            if (Interrupted)
                return;
            // Correction azure-unsupported: refuse Azure SQL Database as Connect-DbaInstance -AzureUnsupported does.
            // There the login SIDs live in the logical server's master and need their own connection, while the
            // pinned detection reads Server.Logins and User.Login on this one, which fails in a user database.
            Server? server = ConnectInstance(instance, azureUnsupported: true);
            if (server is null)
                continue;

            // PS: Where-Object IsAccessible, then Name -In $Database and Name -NotIn $ExcludeDatabase,
            // each applied only when the parameter is truthy. Pinned help documents wildcards for
            // -Database only, which the source's literal -In never honoured; a real database name of
            // this instance stays literal (pinned Remove-DbaDbOrphanUser and Repair-DbaDbOrphanUser
            // pass one), and -ExcludeDatabase stays literal.
            WildcardNameMatcher databaseMatcher = NativeDatabaseSelection.CreateInOperandMatcher(Database, true,
                NativeDatabaseSelection.DatabaseNames(server));
            List<SmoDatabase> databases = new();
            foreach (SmoDatabase candidate in server.Databases)
            {
                if (Interrupted)
                    return;
                if (candidate.IsAccessible &&
                    (!LanguagePrimitives.IsTrue(Database) || databaseMatcher.Matches(candidate.Name)) &&
                    (!LanguagePrimitives.IsTrue(ExcludeDatabase) || !NativeDatabaseSelection.ContainsInOperand(ExcludeDatabase, candidate.Name)))
                    databases.Add(candidate);
            }

            if (databases.Count == 0)
            {
                WriteMessage(MessageLevel.VeryVerbose, "There are no databases to analyse.");
                continue;
            }

            foreach (SmoDatabase database in databases)
            {
                if (Interrupted)
                    return;
                try
                {
                    WriteOrphans(server, database);
                }
                catch (PipelineStoppedException)
                {
                    throw;
                }
                catch (Exception ex)
                {
                    // PS: Stop-Function -Message $_ -Continue - the caught record binds to [string]$Message.
                    string message = (ex as IContainsErrorRecord)?.ErrorRecord?.ToString() ?? ex.Message;
                    StopFunction(message, continueLoop: true);
                    continue;
                }
            }
        }
    }

    private void WriteOrphans(Server server, SmoDatabase database)
    {
        WriteMessage(MessageLevel.Verbose, String.Format("Validating users on database '{0}'.", database));
        List<User> usersToWork = new();
        // ContainmentType is SQL Server 2012+ only, so keep the legacy path for older versions.
        // PS: $null -ne $db.ContainmentType -and $db.ContainmentType -ne None. PowerShell member access reads a
        // property whose getter throws as $null (SMO reports ContainmentType as an unknown property on Azure SQL
        // Database), so such a database is not treated as contained.
        bool isContainedDatabase = false;
        if (server.VersionMajor > 10)
        {
            ContainmentType? containment = ReadContainmentType(database);
            isContainedDatabase = containment.HasValue && containment.Value != ContainmentType.None;
        }
        if (!isContainedDatabase)
        {
            foreach (User user in database.Users)
            {
                // PS: $_.Login, $_.ID, $_.LoginType and $_.Sid are member reads, so a getter that throws reads as $null
                // (on Azure SQL Database SMO resolves User.Login through a further query).
                if (ReadMember(() => user.Login) is string { Length: 0 } && ReadMember(() => user.ID) is int id && id > 4)
                {
                    object? loginType = ReadMember(() => user.LoginType);
                    if ((loginType is LoginType.SqlLogin && (ReadMember(() => user.Sid) as byte[])?.Length == 16) || loginType is LoginType.Certificate)
                        usersToWork.Add(user);
                }
            }
        }
        else
        {
            WriteMessage(MessageLevel.Verbose, String.Format(
                "Skipping SQL login orphan check on contained database '{0}' (ContainmentType: {1}).", database, database.ContainmentType));
        }

        object[]? loginNames = null;
        foreach (User user in database.Users)
        {
            // PS: ($_.Login -notin $server.Logins.Name) is evaluated first for every user; a null Login
            // matches no login name, as in PowerShell.
            loginNames ??= LoginNames(server);
            if (!NativeDatabaseSelection.ContainsName(loginNames, (ReadMember(() => user.Login) as string)!) &&
                ReadMember(() => user.ID) is int id && id > 4 && (ReadMember(() => user.Sid) as byte[])?.Length > 16 &&
                ReadMember(() => user.LoginType) is LoginType.WindowsUser or LoginType.WindowsGroup)
                usersToWork.Add(user);
        }

        if (usersToWork.Count == 0)
        {
            WriteMessage(MessageLevel.Verbose, String.Format("No orphan users found on database '{0}'.", database));
            return;
        }

        WriteMessage(MessageLevel.Verbose, "Orphan users found");
        foreach (User user in usersToWork)
        {
            if (Interrupted)
                return;
            PSObject result = new();
            OutputHelper.AddInstanceProperties(result, server);
            result.Properties.Add(new PSNoteProperty("DatabaseName", database.Name));
            result.Properties.Add(new PSNoteProperty("User", user.Name));
            result.Properties.Add(new PSNoteProperty("SmoUser", user));
            OutputHelper.SetDefaultDisplayPropertySet(result, "ComputerName", "InstanceName", "SqlInstance", "DatabaseName", "User");
            WriteObject(result);
        }
    }

    private static ContainmentType? ReadContainmentType(SmoDatabase database)
    {
        try
        {
            return database.ContainmentType;
        }
        catch (Exception)
        {
            // As PowerShell member access: a property that cannot be read is $null, not an error.
            return null;
        }
    }

    // PS: a member read; a getter that throws reads as $null, as for ContainmentType.
    private static object? ReadMember(Func<object?> read)
    {
        try
        {
            return read();
        }
        catch (Exception)
        {
            return null;
        }
    }

    private static object[] LoginNames(Server server)
    {
        List<object> names = new();
        try
        {
            foreach (Login login in server.Logins)
                names.Add(login.Name);
        }
        catch (Exception ex)
        {
            // PS: $server.Logins.Name enumerates the collection, and an enumeration failure stops the
            // statement with this text; the caller's Stop-Function reports it.
            throw new InvalidOperationException(
                String.Format("The following exception occurred while trying to enumerate the collection: \"{0}\".", ex.Message), ex);
        }
        return names.ToArray();
    }
}
