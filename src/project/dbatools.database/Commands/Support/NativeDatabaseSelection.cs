#nullable enable

using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.Management.Automation;
using Dataplat.Dbatools.Connection;
using Dataplat.Dbatools.Message;
using Dataplat.Dbatools.Parameter;
using Dataplat.Dbatools.Utility;
using Microsoft.SqlServer.Management.Smo;

namespace Dataplat.Dbatools.Commands;

/// <summary>The database-selection subset used by native database-object readers.</summary>
internal static class NativeDatabaseSelection
{
    internal static List<Microsoft.SqlServer.Management.Smo.Database> Gather(DbaBaseCmdlet caller, DbaInstanceParameter[]? instances,
        PSCredential? credential, string[]? include, string[]? exclude,
        Action<Server> connected, Func<bool> interrupted)
    {
        return GatherMatching(caller, instances, credential, include, false, exclude, false, connected, interrupted);
    }

    /// <summary>
    /// Gather with documented wildcard support per filter: a pattern flag is set only where the
    /// calling command's pinned help documents wildcards for that parameter. A caller that gives
    /// Get-DbaDatabase -EnableException passes connectionFailed, which reports each failed connection.
    /// </summary>
    internal static List<Microsoft.SqlServer.Management.Smo.Database> GatherMatching(DbaBaseCmdlet caller,
        DbaInstanceParameter[]? instances, PSCredential? credential, string[]? include, bool includePatterns,
        string[]? exclude, bool excludePatterns, Action<Server> connected, Func<bool> interrupted,
        Action<DbaInstanceParameter, Exception>? connectionFailed = null)
    {
        List<Microsoft.SqlServer.Management.Smo.Database> databases = new();
        foreach (DbaInstanceParameter instance in instances ?? Array.Empty<DbaInstanceParameter>())
        {
            if (interrupted())
                break;
            Server server;
            try
            {
                WriteConnectionMessage(caller, MessageLevel.Debug, "Starting process block");
                SmoConnectionRequest request = new()
                {
                    Instance = instance,
                    SqlCredential = credential,
                    BoundParameters = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "SqlInstance", "SqlCredential" },
                    MessageCallback = (level, message) => WriteConnectionMessage(caller, level, message)
                };
                server = ConnectionService.GetServer(request);
                WriteConnectionMessage(caller, MessageLevel.Debug, "We are finished with this instance");
            }
            catch (Exception exception)
            {
                if (connectionFailed is not null)
                    connectionFailed(instance, exception);
                else
                    Warn(caller, "Failure", exception, ErrorCategory.ConnectionError, instance);
                continue;
            }
            // The caller's callback is not part of Get-DbaDatabase's connection attempt, so its
            // failures propagate unchanged instead of becoming a "Failure" connection warning.
            connected(server);

            // Each instance's own unfiltered database names decide which pattern values are real
            // names and therefore stay literal.
            WildcardNameMatcher includeMatcher = CreateNameMatcher(include, includePatterns, DatabaseNames(server));
            WildcardNameMatcher excludeMatcher = CreateNameMatcher(exclude, excludePatterns, DatabaseNames(server));
            foreach (Microsoft.SqlServer.Management.Smo.Database database in server.Databases)
            {
                if (interrupted())
                    return databases;
                if (LanguagePrimitives.IsTrue(include) && !includeMatcher.Matches(database.Name))
                    continue;
                if (LanguagePrimitives.IsTrue(exclude) && excludeMatcher.Matches(database.Name))
                    continue;
                // Get-DbaDatabase's default Status includes these flags, with any overlap sufficient.
                DatabaseStatus accepted = DatabaseStatus.Normal | DatabaseStatus.Restoring |
                    DatabaseStatus.RecoveryPending | DatabaseStatus.Recovering | DatabaseStatus.Suspect |
                    DatabaseStatus.Offline | DatabaseStatus.Standby | DatabaseStatus.EmergencyMode;
                if ((database.Status & accepted) == 0)
                    continue;

                PSObject wrapped = PSObject.AsPSObject(database);
                foreach (string name in new[] { "ComputerName", "InstanceName", "SqlInstance" })
                    wrapped.Properties.Remove(name);
                OutputHelper.AddInstanceProperties(wrapped, server);
                databases.Add(database);
            }
        }
        return databases;
    }

    /// <summary>
    /// GatherMatching for a reader whose object-array -Database and -ExcludeDatabase bind to
    /// Get-DbaDatabase's string arrays upstream and whose pinned help documents wildcards for both.
    /// Yields each accessible database in order and warns through the caller for each other one.
    /// </summary>
    internal static IEnumerable<Microsoft.SqlServer.Management.Smo.Database> GatherAccessible(DbaBaseCmdlet caller,
        DbaInstanceParameter[]? instances, PSCredential? credential, object[]? include, object[]? exclude,
        Action<Server> connected, Action<string> warn, Func<bool> interrupted)
    {
        string[]? includeNames = include is null ? null :
            (string[])LanguagePrimitives.ConvertTo(include, typeof(string[]), CultureInfo.InvariantCulture);
        string[]? excludeNames = exclude is null ? null :
            (string[])LanguagePrimitives.ConvertTo(exclude, typeof(string[]), CultureInfo.InvariantCulture);
        foreach (Microsoft.SqlServer.Management.Smo.Database database in GatherMatching(caller, instances, credential,
            includeNames, true, excludeNames, true, connected, interrupted))
        {
            if (interrupted())
                yield break;
            if (!database.IsAccessible)
            {
                warn(String.Format("Database {0} is not accessible. Skipping.", database));
                continue;
            }
            yield return database;
        }
    }

    internal static bool ContainsName(object[]? names, string name)
    {
        foreach (object candidate in names ?? Array.Empty<object>())
        {
            if (NameEquals(candidate, name))
                return true;
        }
        return false;
    }

    // Where-Object Name -In over an [object[]] parameter: each supplied value is the left
    // operand, so the name converts to the value's type (database "01" matches 1).
    internal static bool ContainsInOperand(object[]? values, string name)
    {
        foreach (object value in values ?? Array.Empty<object>())
        {
            if (InOperandEquals(value, name))
                return true;
        }
        return false;
    }

    /// <summary>
    /// The ContainsName comparison, plus documented wildcard patterns (rule E+) when
    /// allowPatterns is set; scope lists every object name of the unfiltered collection.
    /// </summary>
    internal static WildcardNameMatcher CreateNameMatcher(object[]? names, bool allowPatterns, IEnumerable<string>? scope)
    {
        return WildcardNameFilter.CreateMatcher(names, allowPatterns, NameEquals, scope);
    }

    /// <summary>
    /// The value-first ContainsInOperand comparison, plus documented wildcard patterns (rule E+)
    /// when allowPatterns is set; only string values containing * or ? are tried as patterns.
    /// </summary>
    internal static WildcardNameMatcher CreateInOperandMatcher(object[]? values, bool allowPatterns, IEnumerable<string>? scope)
    {
        return WildcardNameFilter.CreateMatcher(values, allowPatterns, InOperandEquals, scope);
    }

    /// <summary>Every database name of the instance, before any accessibility or status filter.</summary>
    internal static IEnumerable<string> DatabaseNames(Server server)
    {
        foreach (Microsoft.SqlServer.Management.Smo.Database database in server.Databases)
            yield return database.Name;
    }

    private static bool NameEquals(object candidate, string name)
    {
        return LanguagePrimitives.Equals(name, candidate, true, CultureInfo.InvariantCulture);
    }

    private static bool InOperandEquals(object value, string name)
    {
        return LanguagePrimitives.Equals(value is PSObject wrapped ? wrapped.BaseObject : value, name, true, CultureInfo.InvariantCulture);
    }

    private static void WriteConnectionMessage(DbaBaseCmdlet caller, MessageLevel level, string message)
    {
        MessageService.Write(caller, new MessageService.MessageRequest
        {
            FunctionName = "Connect-DbaInstance", ModuleName = "dbatools", Level = level,
            Message = message, EnableException = false
        });
    }

    private static void Warn(DbaBaseCmdlet caller, string message, Exception exception,
        ErrorCategory category, DbaInstanceParameter instance)
    {
        // Neither caller forwards EnableException into Get-DbaDatabase's own switch parameter.
        MessageService.MessageRequest request = new()
        {
            FunctionName = "Get-DbaDatabase", ModuleName = "dbatools", Level = MessageLevel.Warning,
            Message = message, EnableException = false, FromStopFunction = true,
            File = caller.MyInvocation.ScriptName, Line = caller.MyInvocation.ScriptLineNumber
        };
        object target = MessageService.CollapseTarget(MessageService.ResolveTarget(caller, request, instance));
        Exception transformed = MessageService.ResolveException(caller, request, exception);
        ErrorRecord input = new(transformed, "dbatools_Get-DbaDatabase", category, target);
        ErrorRecord record = new(new Exception(MessageService.GetErrorMessage(input), transformed),
            "dbatools_Get-DbaDatabase", category, target);
        request.Target = target;
        request.ErrorRecord = new[] { record };
        MessageService.Write(caller, request);
        try
        {
            if (caller.SessionState.PSVariable.GetValue("global:Error") is ArrayList errors)
            {
                errors.Insert(0, record);
                int limit;
                if (!Int32.TryParse(Convert.ToString(caller.SessionState.PSVariable.GetValue("MaximumErrorCount"), CultureInfo.InvariantCulture), out limit))
                    limit = 256;
                if (limit >= 0 && errors.Count > limit)
                    errors.RemoveRange(limit, errors.Count - limit);
            }
        }
        catch (Exception)
        {
            // Restricted session state must not replace the original connection failure.
        }
    }
}
